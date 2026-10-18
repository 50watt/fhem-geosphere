#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(decode_json encode_json);
use POSIX qw(strftime tzset);
use FHEM::APIs::Weather::GeoSphereAPI;

our (%defs, %attr, %modules, @queue, $notifications, $throw_http);
$ENV{TZ} = 'Europe/Vienna'; tzset();
$modules{Weather}{AttrList} = 'forecast alerts disable';
sub AttrVal { $attr{$_[0]}{$_[1]} // $_[2] }
sub setDevAttrList { $defs{$_[0]}{'.AttrList'} = $_[1] }
sub HttpUtils_NonblockingGet { die "transport unavailable\n" if $throw_http; push @queue, $_[0] }
sub FHEM::Core::Weather::RetrieveCallbackFn { $notifications++ }
sub CommandDeleteReading {
    my ($name, $regex) = split / /, $_[1], 2;
    for (keys %{$defs{$name}{READINGS} // {}}) {
        delete $defs{$name}{READINGS}{$_} if /^$regex$/;
    }
}
sub fixture {
    open my $fh, '<:raw', "$FindBin::Bin/fixtures/$_[0].json" or die $!;
    local $/; return decode_json(<$fh>);
}
sub iso { strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($_[0])) }
sub epoch { FHEM::APIs::Weather::GeoSphereAPI::_epoch($_[0]) }
my $class = 'FHEM::APIs::Weather::GeoSphereAPI';
my $api = $class->new({devName=>'test', location=>'48.2486,16.3564', apioptions=>'station:11035,cachemaxage:0'});
$defs{test} = {NAME=>'test', TYPE=>'Weather', fhem=>{api=>$api}};
$attr{test}{forecast} = 'hourly,daily';

# Review finding: an expired model must not remain usable after current failure.
$api->{referenceEpoch} = time-40000;
$api->{model} = {};
$api->{cached} = {status=>'ok', forecastStatus=>'ok', forecastValidity=>'up-to-date',
    forecastAge_s=>3600, forecast=>{daily=>[{code=>32}], hourly=>[{code=>32}]}};
$defs{test}{READINGS} = {fc1_temperature=>{VAL=>20}, hfc1_temperature=>{VAL=>20}, unrelated=>{VAL=>'keep'}};
$api->_error('current timeout');
is($api->getWeather->{forecastStatus}, 'stale', 'expired forecast invalidated on station timeout');
is($api->getWeather->{forecastValidity}, 'stale', 'expired forecast not up-to-date');
ok($api->getWeather->{forecastAge_s} >= 40000, 'age recalculated during failure');
is($api->getWeather->{forecastDaysAvailable}, 0, 'expired daily count cleared');
is($api->getWeather->{forecastHoursAvailable}, 0, 'expired hourly count cleared');
ok(!exists $defs{test}{READINGS}{fc1_temperature}, 'expired FHEM daily reading removed on error path');
ok(!exists $defs{test}{READINGS}{hfc1_temperature}, 'expired FHEM hourly reading removed on error path');
is($defs{test}{READINGS}{unrelated}{VAL}, 'keep', 'unrelated reading preserved');
ok(!$api->{model}, 'expired model discarded');

# Review finding: generation alone cannot protect a replacement device object.
$api->_json_request('https://example.invalid/metadata', sub {
    $api->_station_dropdown([{id=>1, name=>'OLD', lat=>48, lon=>16}]);
}, sub { fail('old metadata must not execute failure handler') });
my $late = shift @queue;
$defs{test} = {NAME=>'test', TYPE=>'Weather', fhem=>{api=>bless({}, 'OtherProvider')}, '.AttrList'=>'other'};
$late->{code}=200; $late->{callback}->($late, '', '{}');
is($defs{test}{'.AttrList'}, 'other', 'late metadata cannot modify replacement device');
$api->_station_dropdown([]);
is($defs{test}{'.AttrList'}, 'other', 'direct old adapter call also blocked');
$defs{test}{fhem}{api} = $api;
$api->{metadataDone}=1;
$api->setRetrieveData;
$late = shift @queue;
my $before = $notifications;
delete $defs{test};
$late->{callback}->($late, 'timeout', '');
is($notifications, $before, 'late current response ignored after deletion');
is(scalar @queue, 0, 'deleted provider starts no follow-on request');
$defs{test} = {NAME=>'test', TYPE=>'Weather', fhem=>{api=>$api}};
delete $api->{busy};

# Review finding: keep calendar slots even when the first samples are tomorrow.
for my $case (
    ['2026-10-17T21:30:00Z', '2026-10-17T22:00:00Z', '2026-10-17', '2026-10-18'],
    ['2026-10-24T21:30:00Z', '2026-10-24T22:00:00Z', '2026-10-24', '2026-10-25'],
    ['2026-03-28T22:30:00Z', '2026-03-28T23:00:00Z', '2026-03-28', '2026-03-29'],
) {
    my ($now, $first, $today, $tomorrow) = @$case;
    my $model=fixture('forecast');
    $model->{reference_time}=iso(epoch($now)-1800);
    $model->{timestamps}=[map {iso(epoch($first)+$_*3600)} 0..$#{$model->{timestamps}}];
    my $fc=$api->_forecast($model,epoch($now));
    is($fc->{daily}[0]{date}, $today, "$today fc1 remains today");
    is($fc->{daily}[0]{coverage}, 'missing', 'absent today explicitly missing');
    is($fc->{daily}[0]{low_c}, '', 'no fabricated today temperature');
    is($fc->{daily}[0]{geoSphereSymbolName}, '', 'missing today clears previous symbol');
    is($fc->{daily}[0]{humidity}, '', 'missing today clears previous humidity');
    is($fc->{daily}[1]{date}, $tomorrow, 'fc2 remains tomorrow across DST');
    ok($fc->{hourly}[0]{epoch} > epoch($now), 'future hourly series preserved');
}

# Total precipitation is not synonymous with liquid rain, especially in snow.
my $model=fixture('forecast');
my $now=epoch($model->{timestamps}[0])+60;
my $p=$model->{features}[0]{properties}{parameters};
$p->{rain}={unit=>'kg m-2', data=>[(0.2) x @{$model->{timestamps}}]};
$p->{tp}{data}=[(1.0) x @{$model->{timestamps}}];
$p->{sf}{data}=[(0.8) x @{$model->{timestamps}}];
my $fc=$api->_forecast($model,$now);
is($fc->{hourly}[0]{precipitation},1,'total precipitation includes snow water equivalent');
is($fc->{hourly}[0]{rain1h},0.2,'rain1h only uses liquid rain parameter');
is(epoch($fc->{hourly}[0]{precipitationPeriodEnd})-epoch($fc->{hourly}[0]{precipitationPeriodStart}),3600,'explicit one-hour accumulation interval');
is($fc->{daily}[0]{rain1h},'','single-hour rain not inherited by daily row');
$p->{rain}{data}[1]=undef;
is($api->_forecast($model,$now)->{hourly}[0]{rain1h},'','missing liquid rain not replaced by total precipitation or zero');
$api->_localize_result({forecast=>$fc});
like($fc->{hourly}[0]{precipitationPeriodStart},qr/ CEST$/, 'new interval start displayed locally');

# Review finding: no NWP request when Weather forecast is not selected.
delete $attr{test}{forecast}; $api->setForecast();
$api->{metadataDone}=1;
$api->setRetrieveData;
my $request=shift @queue;
like($request->{url},qr/station\/current/,'observations still requested with forecast disabled');
my $current=fixture('current'); $current->{timestamps}=[iso(time-60)];
$request->{code}=200; $request->{callback}->($request,'',encode_json($current));
is(scalar @queue,0,'disabled forecast issues no NWP request');
is($api->getWeather->{forecastStatus},'disabled','disabled forecast status explicit');
is($api->getWeather->{current}{temperature},13.2,'observations published without forecast');
$attr{test}{forecast}='daily'; $api->setForecast('daily'); $api->setRetrieveData;
$request=shift @queue; $request->{code}=200; $request->{callback}->($request,'',encode_json($current));
like($queue[0]{url},qr/nwp-v2.*tp,rain,sf/, 're-enabled daily forecast fetches total and liquid rain');
@queue=(); delete $api->{busy};

# A newLocation set must survive ordinary updates, but not a changed DEF.
$defs{test}{DEF}='API=GeoSphereAPI location=48.2486,16.3564';
$api->_sync_location;
$api->setLocation(47.1,13.2); $api->_sync_location;
is($api->{lat},47.1,'runtime newLocation persists over location sync');
is($api->{locationSource},'newLocation','runtime source explicit');
$defs{test}{DEF}='API=GeoSphereAPI location=48.1,15.2'; $api->_sync_location;
is($api->{lat},48.1,'changed definition supersedes temporary runtime location');
is($api->getWeather->{forecastStatus},'pending','location change invalidates old forecast immediately');

$throw_http=1;
my $failure;
$api->_json_request('https://example.invalid',sub {fail('no success when transport throws')},sub {$failure=$_[0]});
like($failure,qr/HTTP client:.*transport unavailable/, 'synchronous HTTP client exception handled');
done_testing;
