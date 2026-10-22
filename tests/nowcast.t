use strict;use warnings;use Test::More;use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;
use JSON::PP qw(encode_json decode_json);use POSIX qw(strftime tzset);
$ENV{TZ}='Europe/Vienna';tzset();
our (%defs,%attr,@queue,@deleted);
sub AttrVal {$attr{$_[0]}{$_[1]} // $_[2]}
sub HttpUtils_NonblockingGet {push @queue,$_[0]}
sub CommandDeleteReading {push @deleted,$_[1]}
sub FHEM::Core::Weather::RetrieveCallbackFn {}
sub fixture {open my $f,'<',"$FindBin::Bin/fixtures/$_[0].json" or die $!;local $/;decode_json(<$f>)}
sub clone {decode_json(encode_json($_[0]))}
sub iso {strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($_[0]))}
sub deliver {my ($data,$error)=@_;my $r=shift @queue or die 'no request';$r->{code}=200;$r->{callback}->($r,$error//'',encode_json($data//{}))}
my $c='FHEM::APIs::Weather::GeoSphereAPI';
$defs{test}={NAME=>'test',TYPE=>'Weather'};
my $api=$c->new({devName=>'test',location=>'48.2486,16.3564',apioptions=>'station:11035,nowcast:1,cachemaxage:0'});
$attr{test}{forecast}='hourly,daily';
$defs{test}{fhem}{api}=$api;
my $now=time;my $quarter=int($now/900)*900;
my $data={reference_time=>iso($quarter),timestamps=>[map {iso($quarter+$_*900)} 0..12],features=>[{
 geometry=>{coordinates=>[16.357,48.249]},properties=>{parameters=>{rr=>{unit=>'kg m-2',data=>[0,0.1,0.2,0,0.4,(0)x8]}}}}]};
my $parsed=$api->_nowcast_parse($data,$now);
is(scalar @{$parsed->{rows}},12,'only upcoming 15-minute periods');
is($parsed->{rows}[0]{start},$quarter,'first period may already be underway');
$api->{nowcastData}=$data;$api->{nowcastFetched}=$now;
my $r=$api->_nowcast_readings($now);
is($r->{rainNextHour},'yes','rain expected');is($r->{rainNextHour_mm},0.7,'four period amounts summed in mm');
is($r->{rainNextHourFrom},$c->can('_display_time')->($quarter),'actual first-hour window start');
is($r->{rainNextHourTo},$c->can('_display_time')->($quarter+3600),'actual first-hour window end');
like($r->{rain15m_01_time},qr/CE[ST]+$/,'local time includes timezone');
is($r->{rain15m_01_mm},0.1,'quarter-hour amount not cumulative');
is($r->{nowcastLatitude},48.249,'grid latitude exposed');
is($r->{nowcastQueryLatitude},48.2486,'query location is device location');
my $dry=clone($data);$dry->{features}[0]{properties}{parameters}{rr}{data}=[(0)x13];
$api->{nowcastData}=$dry;is($api->_nowcast_readings($now)->{rainNextHour},'no','confirmed dry only for valid complete data');
for my $case (qw(stale future null negative unit gap short)) {
 my $bad=clone($data);
 $bad->{reference_time}=iso($now-2701) if $case eq 'stale';
 $bad->{reference_time}=iso($now+301) if $case eq 'future';
 $bad->{features}[0]{properties}{parameters}{rr}{data}[1]=undef if $case eq 'null';
 $bad->{features}[0]{properties}{parameters}{rr}{data}[1]=-1 if $case eq 'negative';
 $bad->{features}[0]{properties}{parameters}{rr}{unit}='m' if $case eq 'unit';
 $bad->{timestamps}[2]=iso($quarter+1900) if $case eq 'gap';
 $bad->{timestamps}=[map {iso($quarter+$_*900)} 0..3] if $case eq 'short';
 $api->{nowcastData}=$bad;my $badread=$api->_nowcast_readings($now);
 is($badread->{rainNextHour},'unknown',"$case is never dry");
 is($badread->{nowcastPoints},0,"$case publishes no usable periods");
 ok($badread->{nowcastLastError},"$case diagnostic");
}
$attr{test}{geoSphereNowcast}=0;
is($api->_nowcast_readings($now)->{nowcastStatus},'disabled','attribute can disable API option');
$attr{test}{geoSphereNowcast}=1;
# Exercise all request phases, including an independent failed forecast.
my $current=fixture('current');$current->{timestamps}=[iso(time-120)];
$attr{test}{alerts}=1;$api->{metadataDone}=1;$api->{nowcastFetched}=0;
$api->setRetrieveData;deliver($current);deliver({},'forecast timeout');
like($queue[0]{url},qr/getWarningsForCoords/,'warnings requested before rain');
deliver(fixture('warnings-none'));
like($queue[0]{url},qr/nowcast-v1-15min-1km.*lat_lon=48\.2486,16\.3564/,'nowcast uses device location');
deliver($data);my $w=$api->getWeather;
is($w->{status},'ok','current observations survive forecast failure');
is($w->{forecastStatus},'error','forecast failure exposed');is($w->{warningsStatus},'ok','warnings independent');
is($w->{nowcastStatus},'ok','rain independent of hourly model');is($w->{rainNextHour},'yes','rain published');
$defs{test}{READINGS}{rain15m_12_mm}={VAL=>3};
$api->{nowcastFetched}=0;$api->setRetrieveData;deliver($current);deliver({},'forecast timeout');deliver({},'nowcast timeout');
$w=$api->getWeather;
is($w->{status},'ok','rain failure does not fail measurements');is($w->{warningsStatus},'ok','rain failure does not fail warnings');
is($w->{rainNextHour},'unknown','failed refresh invalidates earlier wet/dry result');
is($w->{rainNextHour_mm},'','failed refresh does not retain old amount');
ok(grep(/rain15m_12_/,@deleted),'old periods removed');
$api->{nowcastData}=$data;$api->{nowcastFetched}=time;
$api->{nowcastError}='';$api->{nowcastFinished}=0;
$api->setRetrieveData;deliver($current);deliver({},'forecast timeout');
is($api->getWeather->{nowcastStatus},'ok','cache recovery clears old request error');
$api->setRetrieveData;deliver({},'observation timeout');
is($api->getWeather->{rainNextHour},'unknown','observation failure invalidates cached rain decision');
is($api->getWeather->{nowcastValidity},'unknown','incomplete pipeline does not claim fresh rain');
$api->{nowcastFetched}=0;$api->_nowcast_request;my $pending=shift @queue;
$api->setLocation(47,15);
$pending->{callback}->($pending,'',encode_json($data));
ok(!exists $api->{nowcastData},'late response for previous location ignored');
is($api->getWeather->{rainNextHour},'unknown','location change clears rain summary');
my $invalid=$c->new({devName=>'invalid',location=>'47,15',apioptions=>'nowcast:2'});
like($invalid->getWeather->{status},qr/0 or 1/,'invalid enable option exposed without terminating FHEM');
done_testing;
