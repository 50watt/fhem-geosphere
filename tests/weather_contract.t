#!/usr/bin/env perl
# Test the provider against an unmodified FHEM Weather core supplied as argument.
# Only the FHEM runtime services and metadata/Readonly dependencies are stubbed.
use strict;
use utf8;
use warnings;
use vars qw(%defs $readingFnAttributes);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(decode_json encode_json);
use Encode qw(decode_utf8);
use POSIX qw(strftime tzset);

BEGIN {
    package Readonly;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::Readonly"} = sub (\[$@%]$) { ${$_[0]} = $_[1]; };
    }
    $INC{'Readonly.pm'} = __FILE__;
    package FHEM::Meta;
    sub import { }
    sub SetInternals { 1 }
    sub Get { 'v1.0.0' }
    $INC{'FHEM/Meta.pm'} = __FILE__;
}
our (%attr,%modules,@queue,@timers);
$modules{Weather}{AttrList}="forecast alerts disable";
sub setDevAttrList {$defs{$_[0]}{".AttrList"}=$_[1]}
sub AttrVal { $attr{$_[0]}{$_[1]} // $_[2] }
sub IsDevice { exists $defs{$_[0]} }
sub IsDisabled { 0 }
sub TimeNow { strftime('%Y-%m-%d %H:%M:%S',localtime) }
sub FmtDateTime { strftime('%Y-%m-%d %H:%M:%S',localtime($_[0])) }
sub Debug { }
sub readingsBeginUpdate { }
sub readingsEndUpdate { }
sub readingsBulkUpdate { $_[0]{READINGS}{$_[1]}{VAL} = $_[2]; }
sub readingsSingleUpdate { readingsBulkUpdate(@_); }
sub Log3 { }
sub InternalTimer { push @timers, [@_]; }
sub RemoveInternalTimer { }
sub CommandDeleteReading {
    my ($unused,$expression) = @_;
    my ($name,$regex) = split / /,$expression,2;
    for (keys %{$defs{$name}{READINGS}}) { delete $defs{$name}{READINGS}{$_} if /^$regex$/; }
}
sub HttpUtils_NonblockingGet { push @queue,$_[0]; }

my $source = shift @ARGV or die "Usage: perl weather_contract.t /absolute/path/to/Weather.pm\n";
$ENV{TZ}='Europe/Vienna'; tzset();
require $source;
my $modern = defined &FHEM::Core::Weather::Define;
my $define = $modern ? \&FHEM::Core::Weather::Define : \&main::Weather_Define;
my $update = $modern ? \&FHEM::Core::Weather::GetUpdate : \&main::Weather_GetUpdate;
my $device = $defs{contract} = {NAME=>'contract',TYPE=>'Weather'};
$device->{READINGS}{fc9_temperature}{VAL} = 42;
$device->{READINGS}{hfc99_temperature}{VAL} = 42;
$device->{READINGS}{unrelated}{VAL} = 'keep';
$attr{contract}{forecast} = 'hourly,daily';
$attr{contract}{forecastLimit} = 24;
$attr{contract}{alerts} = 1;
my $err = $define->($device,['contract','Weather'],{
    API=>'GeoSphereAPI,station:11035,cachemaxage:0',
    location=>'48.2486,16.3564',lang=>'de',interval=>600,
});
is($err,undef,'unmodified Weather Define accepts provider');
isa_ok($device->{fhem}{api},'FHEM::APIs::Weather::GeoSphereAPI');
like($device->{'.AttrList'},qr/forecast alerts disable/,'Weather attributes retained at Define');
like($device->{'.AttrList'},qr/geoSphereAltitude geoSphereStation:auto/,'provider attributes registered at Define');
$attr{contract}{geoSphereStation}='11035';
$attr{contract}{geoSphereAltitude}=198;
$device->{fhem}{api}->_sync_altitude;
$device->{fhem}{api}->_sync_station;
is($device->{fhem}{api}{altitude},198,'saved altitude available after Define');
is($device->{fhem}{api}{station},11035,'saved station selection available after Define');
$device->{fhem}{api}{metadataDone}=1;
$update->($device);
is(scalar @queue,1,'Weather starts nonblocking request');

# Move the recorded fixture series to now so this test stays reproducible.
sub fixture {
    open my $fh,'<:raw',"$FindBin::Bin/fixtures/$_[0].json" or die $!;
    local $/; return decode_json(<$fh>);
}
my $current=fixture('current'); my $forecast=fixture('forecast');
my $observedExtra=$current->{features}[0]{properties}{parameters};
$observedExtra->{TP}={unit=>'°C',data=>[10.8]};
$observedExtra->{GLOW}={unit=>'W/m²',data=>[279]};
$observedExtra->{SO}={unit=>'sec',data=>[120]};
my $predictedExtra=$forecast->{features}[0]{properties}{parameters};
$predictedExtra->{ssrd}={unit=>'W m-2',data=>[(350)x@{$forecast->{timestamps}}]};
$predictedExtra->{sund}={unit=>'s',data=>[(1800)x@{$forecast->{timestamps}}]};
my $epoch = FHEM::APIs::Weather::GeoSphereAPI::_epoch($current->{timestamps}[0]);
my $delta = time - $epoch - 120;
for my $data ($current,$forecast) {
    $data->{timestamps} = [map {strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($_)+$delta))} @{$data->{timestamps}}];
    $data->{reference_time}=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($data->{reference_time})+$delta)) if $data->{reference_time};
}
for my $data ($current,$forecast) {
    my $req=shift @queue; $req->{code}=200;
    $req->{callback}->($req,'',encode_json($data));
}
my $warnings=fixture('warnings-example');
for my $item (@{$warnings->{properties}{warnings}}) {
    $item->{properties}{rawinfo}{start}=time-60;
    $item->{properties}{rawinfo}{end}=time+3600;
}
my $warningRequest=shift @queue;
like($warningRequest->{url},qr/getWarningsForCoords/,'warning API called by Weather update');
$warningRequest->{code}=200;$warningRequest->{callback}->($warningRequest,'',encode_json($warnings));
sub value { $device->{READINGS}{$_[0]}{VAL} }
is(value('warnCount'),2,'Weather writes standard warning count');
is(value('warningsCount'),2,'provider writes independent warning count');
is(value('warn_0_Event'),'Wind','Weather publishes warning event');
is(value('warn_0_level'),'yellow','Weather publishes official severity');
like(decode_utf8(value('warn_0_Impact')),qr/Äste/,'warning umlaut survives Weather reading boundary');
like(decode_utf8(value('hfc1_condition')),qr/bewölkt/,'forecast umlaut survives Weather reading boundary');
is(value('hfc1_geoSphereSymbolName'),'mostly_cloudy','official symbol name survives real core');
is(value('hfc1_conditionSource'),'official GeoSphere sy','real core exposes official symbol source');
is(value('hfc1_icon'),'mostlycloudy','real core selects icon for official symbol');
like(value('fc1_conditionSource'),qr/official GeoSphere sy; representative hour/,'real core discloses daily symbol scope');

is(value('status'),'ok','Weather callback publishes successful status');
is(value('temperature'),13.2,'real core writes current temperature');
is(value('dewPoint'),10.8,'real core publishes station dew point');
is(value('globalRadiation'),279,'real core publishes station radiation');
is(value('sunshineDuration_s'),120,'real core publishes observed sunshine duration');
is(value('dewPointSource'),'GeoSphere station TP','real core exposes observed dew-point source');
like(value('sunshinePeriodStart'),qr/ (?:CET|CEST)$/,'observed sunshine start local');
is(value('hfc1_globalRadiation'),350,'real core publishes hourly radiation');
is(value('hfc1_sunshineDuration_s'),1800,'real core publishes hourly sunshine');
like(value('hfc1_dewPointSource'),qr/calculated/,'real core labels derived forecast dew point');
like(value('hfc1_sunshinePeriodEnd'),qr/ (?:CET|CEST)$/,'hourly sunshine end local');
like(value('fc1_precipitationCoverage'),qr/^(?:complete|partial|unknown|missing)$/,'real core publishes daily amount scope');
ok(defined value('fc1_rainTotal_mm'),'real core exposes daily liquid rain field');
ok(defined value('fc1_sunshineCoverage'),'real core exposes daily sunshine scope');
ok(defined value('fc1_summaryCondition'),'real core exposes separate daily summary');
is($device->{fhem}{api}->getWeather->{apiVersion},'0.2.10','new provider loaded by unmodified core');
for my $reading (qw(measurementTime pubDate current_date_time forecastReferenceTime warningsFetchedAt hfc1_timestamp fc1_periodStart warn_0_Start)) {
 like(value($reading),qr/^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2} (?:CET|CEST)$/,"real core local display for $reading");
}
is(value('pressure'),1017.4,'real core writes reduced pressure');
ok(defined value('fc1_low_c'),'HomeMode forecast low available');
ok(defined value('fc2_high_c'),'HomeMode tomorrow high available');
ok(defined value('fc2_condition'),'HomeMode tomorrow condition available');
ok(defined value('hfc1_precipitation'),'hourly precipitation available');
like(value('.license'),qr/GeoSphere Austria.*CC BY 4.0/,'attribution published');
ok(@timers,'Weather rearms update timer');
is(value('lastError'),'','lastError cleared on success');
ok(!exists $device->{READINGS}{fc9_temperature},'obsolete daily record removed');
ok(!exists $device->{READINGS}{hfc99_temperature},'obsolete hourly record removed');
is(value('unrelated'),'keep','unrelated reading retained');
$update->($device);
my $req=shift @queue;
$req->{callback}->($req,'timeout','');
like(value('lastError'),qr/timeout/,'real core exposes request failure');
is(value('validity'),'stale','failed update marked stale');
is(value('temperature'),13.2,'failed update does not fabricate a new temperature');
$device->{fhem}{api}{warningsFetched}=0;
$update->($device);
for my $data ($current) {
    my $p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($data));
}
my $p=shift @queue;$p->{callback}->($p,'warning timeout','');
is(value('status'),'ok','warning-only failure preserves weather success');
is(value('warnCount'),'unknown','standard count unknown on warning failure');
is(value('warningsStatus'),'error','warning-only failure status');
is(value('warn_0_Event'),'Wind','last-known warning retained with error status');
$update->($device);
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($current));
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json(fixture('warnings-none')));
is(value('warningsStatus'),'ok','warning state recovers');
is(value('warnCount'),0,'successful empty response clears standard count');
ok(!exists $device->{READINGS}{warn_0_Event},'expired/cancelled warning readings removed');
# Forecast-only failure must keep real Weather readings and warning updates alive.
my $api=$device->{fhem}{api};delete @{$api}{qw(model modelFetched)};$api->{warningsFetched}=0;
my $freshCurrent=decode_json(encode_json($current));$freshCurrent->{features}[0]{properties}{parameters}{TL}{data}[0]=12.9;
my $staleForecast=decode_json(encode_json($forecast));
$staleForecast->{reference_time}=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time-40000));
$update->($device);
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($freshCurrent));
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($staleForecast));
like($queue[0]{url},qr/getWarningsForCoords/,'real Weather still requests warnings after stale forecast');
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json(fixture('warnings-none')));
is(value('temperature'),12.9,'real Weather publishes newer observation despite stale forecast');
is(value('validity'),'up-to-date','real Weather observation validity independent');
is(value('forecastStatus'),'stale','real Weather exposes forecast-only stale status');
is(value('warningsStatus'),'ok','real Weather warning status unaffected by forecast');
is(value('lastError'),'','forecast error kept in separate forecastLastError');
like(value('forecastLastError'),qr/forecast stale/,'separate forecast diagnostic retained');
ok(!exists $device->{READINGS}{hfc1_temperature},'old hourly forecast removed on real core');
ok(!exists $device->{READINGS}{fc1_low_c},'old daily forecast removed on real core');
$api->{warningsFetched}=0;$update->($device);
for my $d ($freshCurrent,$forecast,fixture('warnings-none')) {
 $p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($d));
}
is(value('forecastStatus'),'ok','real core forecast recovery');
ok(defined value('hfc1_temperature'),'real core hourly forecast restored');
is(value('forecastLastError'),'','real core forecast error cleared on recovery');

my $invalidDevice = $defs{invalidContract} = {NAME=>'invalidContract',TYPE=>'Weather'};
my $invalidError = $define->($invalidDevice,['invalidContract','Weather'],{
    API=>'GeoSphereAPI',location=>'48.2213',lang=>'de',interval=>600,
});
is($invalidError,undef,'invalid provider configuration does not escape Weather Define');
isa_ok($invalidDevice->{fhem}{api},'FHEM::APIs::Weather::GeoSphereAPI');
like($invalidDevice->{READINGS}{state}{VAL},
    qr/configuration error: location must be latitude,longitude; for example location=48\.2486,16\.3564/,
    'configuration error immediately visible in state');
like($invalidDevice->{READINGS}{lastError}{VAL},qr/location must be latitude,longitude/,
    'configuration cause immediately visible in lastError');
my $invalidAttributeDevice = $defs{invalidAttributeContract} = {
    NAME=>'invalidAttributeContract',TYPE=>'Weather',
};
$define->($invalidAttributeDevice,['invalidAttributeContract','Weather'],{
    API=>'GeoSphereAPI',location=>'48.2213,16.3157',lang=>'de',interval=>600,
});
$attr{invalidAttributeContract}{geoSphereAltitude}='invalid';
my $attributeUpdate = eval { $update->($invalidAttributeDevice); 1 };
ok($attributeUpdate,'invalid altitude does not escape Weather update');
like($invalidAttributeDevice->{READINGS}{lastError}{VAL},
    qr/configuration error: invalid geoSphereAltitude/,
    'invalid altitude is exposed as configuration error');
delete $attr{invalidAttributeContract}{geoSphereAltitude};
$attr{invalidAttributeContract}{geoSphereStation}='invalid';
$attributeUpdate = eval { $update->($invalidAttributeDevice); 1 };
ok($attributeUpdate,'invalid station does not escape Weather update');
like($invalidAttributeDevice->{READINGS}{lastError}{VAL},
    qr/configuration error: invalid geoSphereStation/,
    'invalid station is exposed as configuration error');
$api->{nowcastOption}=1;
# Use the API option because the integration device has its own name.
my $quarter=int(time/900)*900;
my $rain={reference_time=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($quarter)),
 timestamps=>[map {strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($quarter+$_*900))} 1..12],
 features=>[{geometry=>{coordinates=>[16.3564,48.2486]},properties=>{parameters=>{rr=>{unit=>'kg m-2',data=>[(0.2)x12]}}}}]};
$update->($device);
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($freshCurrent));
like($queue[0]{url},qr/nowcast-v1-15min-1km/,'real core triggers optional nowcast');
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($rain));
is(value('nowcastStatus'),'ok','real core publishes rain status');
is(value('rainNextHour'),'yes','real core publishes rain flag');
is(value('rainNextHour_mm'),0.8,'real core publishes rain amount');
is(value('rain15m_01_mm'),0.2,'real core publishes flat quarter-hour readings');
like(value('rain15m_01_time'),qr/(?:CET|CEST)$/,'real core publishes local rain time');
$api->{nowcastOption}=0;$update->($device);
$p=shift @queue;$p->{code}=200;$p->{callback}->($p,'',encode_json($freshCurrent));
is(value('nowcastStatus'),'disabled','real core disables rain independently');
ok(!exists $device->{READINGS}{rain15m_01_mm},'real core removes periods after disabling');
$device->{fhem}{api}->setLocation(47.9,13.7);
is(value('warningsStatus'),'pending','location change invalidates warning status immediately');
is(value('warnCount'),'unknown','location change is not a no-warning confirmation');
$api->{referenceEpoch}=time-40000;
$api->{metadataDone}=1;
$api->{cached}{forecastStatus}='ok';
$api->{cached}{forecastValidity}='up-to-date';
$api->{cached}{forecast}={daily=>[{code=>32}],hourly=>[{code=>32}]};
$device->{READINGS}{fc1_temperature}{VAL}=20;
$device->{READINGS}{hfc1_temperature}{VAL}=20;
$update->($device);
$p=shift @queue;$p->{callback}->($p,'station timeout','');
is(value('forecastStatus'),'stale','real core invalidates expired forecast during station failure');
is(value('forecastValidity'),'stale','real core does not claim expired forecast up-to-date');
ok(value('forecastAge_s')>=40000,'real core exposes recalculated model age on station failure');
ok(!exists $device->{READINGS}{hfc1_temperature},'real core error path clears expired hourly data');
ok(!exists $device->{READINGS}{fc1_temperature},'real core error path clears expired daily data');
done_testing;

