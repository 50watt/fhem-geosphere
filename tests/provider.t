#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP qw(decode_json encode_json);
use Encode qw(decode_utf8 encode_utf8);
use FindBin;
use lib "$FindBin::Bin/../lib";
use POSIX qw(tzset);
use Time::Local qw(timegm timelocal);
use FHEM::APIs::Weather::GeoSphereAPI;

$ENV{TZ} = 'Europe/Vienna'; tzset();
my $CLASS = 'FHEM::APIs::Weather::GeoSphereAPI';
sub fixture {
    my ($name) = @_;
    open my $fh, '<:raw', "$FindBin::Bin/fixtures/$name.json" or die $!;
    local $/; return decode_json(<$fh>);
}
sub clone { return decode_json(encode_json($_[0])); }
sub provider { my $api=$CLASS->new({devName=>'test',location=>'48.2486,16.3564',language=>'de',apioptions=>'station:11035,'.($_[0] // '')}); $api->setForecast('hourly,daily'); return $api; }
my $api = provider();
$api->_sync_station;
my $current = fixture('current');
my $forecast = fixture('forecast');
my $now = FHEM::APIs::Weather::GeoSphereAPI::_epoch($current->{timestamps}[0]) + 120;
my $obs = $api->_current($current,$now);
is($obs->{readings}{temperature},13.2,'station temperature');
is($obs->{readings}{humidity},85,'station humidity');
is($obs->{readings}{pressure},1017.4,'reduced pressure, not station pressure');
is($obs->{readings}{stationPressure},992.6,'station pressure retained separately');
is($obs->{readings}{wind},4,'m/s converted to km/h');
is($obs->{readings}{wind_gust},9,'gust converted to km/h');
is($obs->{readings}{rain10min_mm},0,'dry observation is a valid zero');
is($obs->{readings}{code},48,'no invented observed weather condition');
is($obs->{readings}{apparentTemperature},'','no invented feels-like temperature');
my $fc = $api->_forecast($forecast,$now);
ok(@{$fc->{hourly}} > 24,'hourly forecasts');
is($fc->{daily}[0]{date},'2026-10-17','fc1 is today, as required by HomeMode');
is($fc->{daily}[1]{date},'2026-10-18','fc2 is tomorrow');
is($fc->{daily}[0]{coverage},'partial','evening is not a complete day');
is($fc->{daily}[1]{coverage},'complete','tomorrow has full hourly coverage');
is($fc->{daily}[1]{samples},24,'24 samples in normal day');
ok($fc->{hourly}[0]{pressure} > 900 && $fc->{hourly}[0]{pressure} < 1100,'Pa to hPa');
is($fc->{hourly}[0]{timestamp},'2026-10-17T20:00+00:00','past forecast steps excluded');
ok(defined $fc->{daily}[0]{precipitationCoverage},'daily interval rainfall coverage declared');
is($fc->{hourly}[0]{condition},'Stark bewölkt','official GeoSphere mostly-cloudy symbol');

for my $case (
    ['old observation',sub {$api->_current($current,$now+1900)}],
    ['future observation',sub {$api->_current($current,$now-900)}],
    ['old model',sub {$api->_forecast($forecast,$now+30000)}],
    ['invalid calendar date',sub {FHEM::APIs::Weather::GeoSphereAPI::_epoch('2026-02-30T12:00Z')}],
    ['invalid hour',sub {FHEM::APIs::Weather::GeoSphereAPI::_epoch('2026-10-17T25:00Z')}],
) {
    eval {$case->[1]->()}; ok($@,$case->[0].' rejected');
}
for my $case (
    ['incomplete location', {location=>'48.2'}],
    ['invalid location', {location=>'48.2,999'}],
    ['unknown option', {location=>'48.2,16.3',apioptions=>'secret:abc'}],
    ['invalid timeout', {location=>'48.2,16.3',apioptions=>'timeout:0'}],
) {
    my $invalid;
    my $ok = eval { $invalid = $CLASS->new($case->[1]); 1 };
    ok($ok, $case->[0].' does not terminate FHEM');
    isa_ok($invalid, $CLASS, $case->[0].' returns provider');
    like($invalid->getWeather->{status}, qr/(?:location|option|timeout)/,
        $case->[0].' is exposed as provider status');
    unlike($invalid->getWeather->{status}, qr/\s$/,
        $case->[0].' status has no trailing whitespace');
}
is(FHEM::APIs::Weather::GeoSphereAPI::_epoch('2026-10-17T21:20:00+02:00'),$now-120,'ISO offset supported');
for my $value (undef,-999,'NaN','Inf','oops') {
    ok(!defined FHEM::APIs::Weather::GeoSphereAPI::_number($value),'invalid numeric value rejected');
}
my $bad = clone($current); $bad->{features}[0]{properties}{parameters}{TL}{data}[0] = undef;
eval {$api->_current($bad,$now)}; like($@,qr/missing essential/,'null is not zero');
$bad = clone($current); $bad->{features}[0]{properties}{parameters}{RF}{data}[0] = 130;
eval {$api->_current($bad,$now)}; like($@,qr/physical range/,'impossible humidity rejected');
$bad = clone($current); $bad->{features}[0]{properties}{parameters}{FF}{unit} = 'km/h';
eval {$api->_current($bad,$now)}; like($@,qr/unit/,'changed units rejected');
$bad = clone($current); $bad->{features}[0]{properties}{station} = '11036';
eval {$api->_current($bad,$now)}; like($@,qr/wrong station/,'wrong station rejected');
$bad = clone($current); $bad->{features}[0]{properties}{parameters}{RR}{data}[0] = undef;
is($api->_current($bad,$now)->{readings}{rain10min_mm},'','missing rain is unknown');
$bad = clone($forecast); $bad->{timestamps}[1] = $bad->{timestamps}[0];
eval {$api->_forecast($bad,$now)}; like($@,qr/not hourly/,'duplicate forecast timestamps rejected');

# Generate complete UTC hourly series spanning the local DST transition day.
for my $case (['2026-10-25',25], ['2026-03-29',23]) {
    my ($date,$hours) = @$case;
    my ($year,$month,$day) = split /-/,$date;
    my $start = timelocal(0,0,0,$day,$month-1,$year);
    my $data = clone($forecast);
    $data->{reference_time} = POSIX::strftime('%Y-%m-%dT%H:%MZ',gmtime($start));
    $data->{timestamps} = [map {POSIX::strftime('%Y-%m-%dT%H:%MZ',gmtime($start+$_*3600))} 0..$hours-1];
    for my $p (values %{$data->{features}[0]{properties}{parameters}}) {
        $p->{data} = [map {$p->{data}[0]} 0..$hours-1];
    }
    my $dst = $api->_forecast($data,$start);
    is($dst->{daily}[0]{samples},$hours,"$date has $hours samples");
    is($dst->{daily}[0]{coverage},'complete',"$date complete across DST");
}

# Exercise the real asynchronous provider entry point with a fake HTTP transport.
our (%defs, @queue, $notifications);
$notifications = 0;

$defs{nowcastDisplay} = {
    NAME => 'nowcastDisplay',
    TYPE => 'Weather',
    LANG => 'de',
    READINGS => {
        nowcastStatus        => { VAL => 'ok' },
        nowcastValidity      => { VAL => 'up-to-date' },
        nowcastReferenceTime => { VAL => '17.10.2026 12:00:00 CEST' },
        nowcastPoints        => { VAL => 3 },
        rain15m_01_mm          => { VAL => 0 },
        rain15m_01_periodStart => { VAL => '17.10.2026 12:00:00 CEST' },
        rain15m_01_time        => { VAL => '17.10.2026 12:15:00 CEST' },
        rain15m_02_mm          => { VAL => 0.2 },
        rain15m_02_periodStart => { VAL => '17.10.2026 12:15:00 CEST' },
        rain15m_02_time        => { VAL => '17.10.2026 12:30:00 CEST' },
        rain15m_03_mm          => { VAL => 1.5 },
        rain15m_03_periodStart => { VAL => '17.10.2026 12:30:00 CEST' },
        rain15m_03_time        => { VAL => '17.10.2026 12:45:00 CEST' },
    },
};
my $nowcastHtml = GeoSphereNowcastAsHtml( 'nowcastDisplay', 2 );
like( $nowcastHtml, qr/Niederschlags-Nowcast/, 'nowcast HTML has localized title' );
like( $nowcastHtml, qr/12:15/, 'nowcast HTML contains first interval end' );
like( $nowcastHtml, qr/12:30/, 'nowcast HTML contains second interval end' );
unlike( $nowcastHtml, qr/12:45/, 'requested maximum limits nowcast bars' );
like( $nowcastHtml, qr/aktuell/, 'running quarter hour is identified' );
like( $nowcastHtml, qr/GeoSphere Austria/, 'nowcast attribution is visible' );
ok( !utf8::is_utf8($nowcastHtml), 'public nowcast HTML uses FHEMWEB UTF-8 octets' );
$defs{nowcastDisplay}{READINGS}{nowcastStatus}{VAL} = 'error';
$defs{nowcastDisplay}{READINGS}{nowcastLastError} =
  { VAL => encode_utf8('Übertragung <transport>') };
$nowcastHtml = GeoSphereNowcastAsHtml( 'nowcastDisplay', 12 );
my $decodedNowcastHtml = decode_utf8($nowcastHtml);
like( $decodedNowcastHtml, qr/Übertragung &lt;transport&gt;/,
    'UTF-8 nowcast error is decoded once and HTML escaped' );

sub HttpUtils_NonblockingGet { push @queue, $_[0]; }
{
    no warnings 'redefine';
    *FHEM::Core::Weather::RetrieveCallbackFn = sub {$notifications++};
}
my $delta = time - $now;
my $transportCurrent = clone($current);
my $transportForecast = clone($forecast);
for my $data ($transportCurrent,$transportForecast) {
    $data->{timestamps} = [map {POSIX::strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($_)+$delta))} @{$data->{timestamps}}];
    $data->{reference_time} = POSIX::strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($data->{reference_time})+$delta)) if $data->{reference_time};
}
my $live = provider();
$live->{metadataDone}=1;
$defs{test}{fhem}{api} = $live;
$live->setRetrieveData;
is(scalar @queue,1,'one request pending');
$live->setRetrieveData;
is(scalar @queue,1,'concurrent update suppressed');
my $req = shift @queue;
like($req->{url},qr/station_ids=11035/,'station URL');
$req->{code}=200; $req->{callback}->($req,'',encode_json($transportCurrent));
is(scalar @queue,1,'forecast follows current request');
$req = shift @queue;
like($req->{url},qr/nwp-v2-1h-1km.*lat_lon=48.2486,16.3564/,'forecast URL');
$req->{code}=200; $req->{callback}->($req,'',encode_json($transportForecast));
is($notifications,1,'exactly one Weather callback');
is($live->getWeather->{status},'ok','complete result published');
$live->setRetrieveData;
is(scalar @queue,0,'successful result cached');
is($notifications,2,'cache hit invokes callback');
$live->{fetchTime}=0;
$live->setRetrieveData; $req = shift @queue;
$req->{callback}->($req,'timeout','');
like($live->getWeather->{status},qr/timeout/,'transport error visible');
is($live->getWeather->{validity},'stale','error invalidates result');
is($live->getWeather->{current}{temperature},13.2,'last good reading retained');
$live->setRetrieveData; $req = shift @queue; $req->{code}=200;
$req->{callback}->($req,'','{}');
like($live->getWeather->{status},qr/expected one/,'invalid schema handled');
$live->setRetrieveData; $req = shift @queue; $req->{code}=200;
$req->{callback}->($req,'','{broken');
like($live->getWeather->{status},qr/invalid JSON/,'malformed JSON handled');
$live->setRetrieveData; $req = shift @queue;
$req->{code}=503; $req->{callback}->($req,'','{}');
like($live->getWeather->{status},qr/HTTP 503/,'HTTP status handled');
$live->setRetrieveData; $req = shift @queue;
$live->setLocation(48.3,16.4);
my $before = $notifications;
$req->{callback}->($req,'timeout','');
is($notifications,$before,'response from previous location ignored');
ok(!$live->{model},'location change invalidates forecast cache');
done_testing;
