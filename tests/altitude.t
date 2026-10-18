use strict; use warnings; use Test::More; use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;
our (%defs,%attr,%modules);
$modules{Weather}{AttrList}='forecast alerts disable';
sub AttrVal {$attr{$_[0]}{$_[1]} // $_[2]}
sub ReadingsVal {$defs{$_[0]}{READINGS}{$_[1]}{VAL} // $_[2]}
sub setDevAttrList {$defs{$_[0]}{'.AttrList'}=$_[1]}
sub CommandAttr {my ($d,$a,$v)=split / /,$_[1],3;$attr{$d}{$a}=$v;return}
sub CommandDeleteAttr {my ($d,$a)=split / /,$_[1];delete $attr{$d}{$a};return}
sub FHEM::Core::Weather::RetrieveCallbackFn {}
$attr{global}={latitude=>48.2486,longitude=>16.3564,altitude=>200};
$defs{test}={NAME=>'test',TYPE=>'Weather',DEF=>'API=GeoSphereAPI'};
my $api=FHEM::APIs::Weather::GeoSphereAPI->new({devName=>'test',location=>'1,2'});
$defs{test}{fhem}{api}=$api;
is($api->{altitude},200,'global altitude at global location');
is($api->{altitudeSource},'global','height source exposed');
like($defs{test}{'.AttrList'},qr/geoSphereAltitude/,'altitude attribute registered before metadata');
like($defs{test}{'.AttrList'},qr/forecast alerts disable/,'base Weather attributes preserved');
my @stations=(
 {id=>1,name=>'NEAR_HIGH',lat=>48.2486,lon=>16.357,altitude=>450},
 {id=>2,name=>'FAR_LOW',lat=>48.26,lon=>16.3564,altitude=>205},
 {id=>3,name=>'NO_HEIGHT',lat=>48.2486,lon=>16.3564},
);
is($api->_rank_stations(\@stations)->[0]{id},2,'similar height beats closer hill station');
ok($api->_station_score($stations[0])>$api->_station_score($stations[1]),'height penalty included in score');
is($api->_rank_stations(\@stations)->[-1]{id},3,'missing station height penalised');
$defs{test}{DEF}='API=GeoSphereAPI location=47.1,13.2';
$api->_sync_location; $api->_sync_altitude;
ok(!defined $api->{altitude},'remote location does not inherit home height');
is($api->{altitudeSource},'missing','missing target height explicit');
$attr{test}{geoSphereAltitude}=900;
$api->_sync_altitude;
is($api->{altitude},900,'device height overrides global');
is($api->{altitudeSource},'device','device altitude source');
$api->{selectedAuto}=1; $api->{station}=1; $api->{stationChoice}='auto';$api->{metadataDone}=1;
$attr{test}{geoSphereAltitude}=901;$api->_sync_altitude;
ok(!$api->{selectedAuto} && !$api->{metadataDone} && !$api->{station},'height change forces new auto selection');
$attr{test}{geoSphereAltitude}=-50;$api->_sync_altitude;
is($api->{altitude},-50,'below-sea-level height accepted');
$attr{test}{geoSphereAltitude}='oops';eval {$api->_sync_altitude};like($@,qr/invalid geoSphereAltitude/,'malformed height rejected');
$attr{test}{geoSphereAltitude}=10000;eval {$api->_sync_altitude};like($@,qr/invalid geoSphereAltitude/,'out-of-range height rejected');
delete $attr{test}{geoSphereAltitude};$api->_sync_altitude;
my $ranked=$api->_rank_stations(\@stations);
is($ranked->[0]{id},3,'distance-only ranking at remote location');
$defs{test}{DEF}='API=GeoSphereAPI location=48.2486,16.3564';
$api->_sync_location;$api->_sync_altitude;
is($api->{altitude},200,'explicit coordinates matching global may use global height');
$api->{stationOption}='auto'; $api->{stationChoice}='auto';
$defs{test}{READINGS}={
 selectedStation=>{VAL=>1},selectedStationLocation=>{VAL=>'48.2486,16.3564'},
 stationSelection=>{VAL=>'auto'},selectedStationTargetAltitude=>{VAL=>200},
 stationSelectionMethod=>{VAL=>'distance-altitude'},
};
$api->_sync_station;
is($api->{selectedAuto},1,'matching persisted selection restored');
delete $api->{selectedAuto};$defs{test}{READINGS}{selectedStationTargetAltitude}{VAL}=450;
$api->_sync_station;
ok(!$api->{selectedAuto},'persisted selection for different altitude ignored');
$attr{test}{userattr}='other:one geoSphereStation:auto,OLD';$attr{test}{geoSphereStation}='auto';
$api->_station_dropdown(\@stations);
is($attr{test}{userattr},'other:one','upgrade preserves unrelated custom attributes');
is($attr{test}{geoSphereStation},'auto','upgrade preserves chosen station');
is($modules{Weather}{AttrList},'forecast alerts disable','global Weather attribute list unchanged');
is(scalar(()=$defs{test}{'.AttrList'}=~/geoSphereAltitude/g),1,'no duplicate altitude declarations');
# Exercise the real asynchronous metadata/probe selection path.
our @queue;
sub HttpUtils_NonblockingGet {push @queue,$_[0]}
$attr{test}{geoSphereAltitude}=200; $api->_sync_altitude;
$attr{test}{geoSphereStation}='auto'; delete $api->{selectedAuto}; delete $api->{station};
$defs{test}{READINGS}={};
$api->setRetrieveData;
my $request=shift @queue;
like($request->{url},qr{/metadata$},'auto selection requests metadata');
require JSON::PP; require POSIX;
$request->{code}=200;
$request->{callback}->($request,'',JSON::PP::encode_json({stations=>[map {+{%$_,is_active=>1}} @stations]}));
$request=shift @queue;
like($request->{url},qr/station_ids=2,1,3$/,'probe candidates ordered by altitude and distance');
open my $fh,'<',"$FindBin::Bin/fixtures/current.json" or die $!;
my $current=JSON::PP::decode_json(do {local $/; <$fh>}); close $fh;
$current->{timestamps}=[POSIX::strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(time-120))];
my $template=$current->{features}[0];
$current->{features}=[map {my $f=JSON::PP::decode_json(JSON::PP::encode_json($template));
 $f->{properties}{station}=$_->{id}; $f} @stations];
$request->{code}=200;$request->{callback}->($request,'',JSON::PP::encode_json($current));
is($api->{selectedAuto},2,'fresh lower station selected despite closer high station');
like($queue[0]{url},qr/station_ids=2$/,'weather fetched from selected lower station');
done_testing;
