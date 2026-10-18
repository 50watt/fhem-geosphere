use strict; use warnings; use Test::More; use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;
use JSON::PP qw(encode_json decode_json);use POSIX qw(strftime);
our (%defs,%attr,@queue);
sub AttrVal {$attr{$_[0]}{$_[1]} // $_[2]}
sub readingsSingleUpdate {$_[0]{READINGS}{$_[1]}{VAL}=$_[2]}
sub HttpUtils_NonblockingGet {push @queue,$_[0]}
sub FHEM::Core::Weather::RetrieveCallbackFn {}
sub fixture {open my $f,'<',"$FindBin::Bin/fixtures/$_[0].json" or die $!;local $/;decode_json(<$f>)}
sub clone {decode_json(encode_json($_[0]))}
sub deliver {
 my ($data,$error,$code)=@_;my $r=shift @queue or die 'no request';$r->{code}=$code//200;
 $r->{callback}->($r,$error//'',encode_json($data//{}));
}
my $current=fixture('current');my $forecast=fixture('forecast');my $empty=fixture('warnings-none');
my $epoch=FHEM::APIs::Weather::GeoSphereAPI::_epoch($current->{timestamps}[0]);my $delta=time-$epoch-120;
for my $d ($current,$forecast) {
 $d->{timestamps}=[map {strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($_)+$delta))} @{$d->{timestamps}}];
 $d->{reference_time}=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($d->{reference_time})+$delta)) if $d->{reference_time};
}
$defs{test}={NAME=>'test',TYPE=>'Weather'};$attr{test}{alerts}=1;
my $api=FHEM::APIs::Weather::GeoSphereAPI->new({devName=>'test',location=>'48.2486,16.3564',apioptions=>'station:11035,cachemaxage:0'});
$defs{test}{fhem}{api}=$api;$api->{metadataDone}=1;
$attr{test}{forecast}='hourly,daily';
my $stale=clone($forecast);$stale->{reference_time}=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time-40000));
$api->setRetrieveData;deliver($current);deliver($stale);
like($queue[0]{url},qr/getWarningsForCoords/,'stale forecast does not block warning request');
deliver($empty);
my $w=$api->getWeather;
is($w->{status},'ok','fresh observations still published');
is($w->{current}{temperature},13.2,'real observation temperature retained');
is($w->{validity},'up-to-date','observation validity independent');
is($w->{forecastStatus},'stale','forecast marked stale');
is($w->{forecastValidity},'stale','forecast validity separate');
like($w->{forecastLastError},qr/reference age .*exceeds/,'forecast diagnostic includes age limit');
is($w->{forecastHoursAvailable},0,'stale forecast not published');
is(@{$w->{forecast}{daily}},0,'daily stale forecast not published');
is($w->{warningsStatus},'ok','warnings still refreshed');
is($w->{warningsCount},0,'successful empty warning response confirms zero');
ok($w->{forecastAge_s}>=40000,'forecast age exposed');
for my $case ('timeout','http','json','schema','future') {
 $api->{warningsFetched}=0;
 $api->setRetrieveData;deliver($current);
 if($case eq 'timeout'){deliver({},'timeout')}
 elsif($case eq 'http'){deliver({},'',503)}
 elsif($case eq 'json'){my $r=shift @queue;$r->{code}=200;$r->{callback}->($r,'','{broken')}
 elsif($case eq 'schema'){deliver({})}
 else {my $future=clone($forecast);$future->{reference_time}=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time+1000));deliver($future)}
 like($queue[0]{url},qr/getWarningsForCoords/,"$case forecast failure still calls warning API");
 deliver($empty);
 is($api->getWeather->{status},'ok',"$case failure preserves current weather");
 is($api->getWeather->{forecastStatus},'error',"$case forecast error visible");
 is($api->getWeather->{warningsStatus},'ok',"$case independent warnings remain successful");
}
$api->{warningsFetched}=0;$api->setRetrieveData;deliver($current);deliver($forecast);deliver($empty);
is($api->getWeather->{forecastStatus},'ok','fresh model recovers');
is($api->getWeather->{forecastLastError},'','recovery clears forecast error');
ok($api->getWeather->{forecastHoursAvailable}>0,'fresh forecast published after recovery');
# A still-valid cached forecast can survive a failed refresh, with an error diagnostic.
$api->{modelFetched}=0;$api->setRetrieveData;deliver($current);deliver({},'model timeout');
is($api->getWeather->{forecastStatus},'ok','valid previous model retained on failed refresh');
like($api->getWeather->{forecastLastError},qr/model timeout/,'failed refresh disclosed despite usable model');
# Observations retain their own freshness checks.
my $old=clone($current);$old->{timestamps}=[strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time-7200))];
$api->setRetrieveData;deliver($old);
is($api->getWeather->{validity},'stale','expired observations still rejected');
like($api->getWeather->{status},qr/current/,'observation failure remains explicit');
done_testing;
