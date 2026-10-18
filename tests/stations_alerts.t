use strict;
use warnings;
use utf8;
use Test::More;
use JSON::PP qw(decode_json encode_json);
use Encode qw(decode_utf8);
use FindBin;
use lib "$FindBin::Bin/../lib";
use FHEM::APIs::Weather::GeoSphereAPI;
use POSIX qw(strftime tzset);
$ENV{TZ}='Europe/Vienna'; tzset();
our (%defs,%attr,%modules,@queue,$notifications);
$modules{Weather}{AttrList}="forecast alerts disable";
sub setDevAttrList {$defs{$_[0]}{".AttrList"}=$_[1];}
sub CommandAttr {my ($d,$a,$v)=split / /,$_[1],3;$attr{$d}{$a}=$v;return}
sub CommandDeleteAttr {my ($d,$a)=split / /,$_[1];delete $attr{$d}{$a};return}
sub AttrVal {return $attr{$_[0]}{$_[1]} // $_[2];}
sub ReadingsVal {return $defs{$_[0]}{READINGS}{$_[1]}{VAL} // $_[2];}
sub readingsSingleUpdate {$defs{$_[0]{NAME}}{READINGS}{$_[1]}{VAL}=$_[2];}
sub addToDevAttrList {$attr{$_[0]}{userattr}=join ' ',grep {length} ($attr{$_[0]}{userattr}//'',$_[1]);}
sub HttpUtils_NonblockingGet {push @queue,$_[0];}
sub FHEM::Core::Weather::RetrieveCallbackFn {$notifications++;}
sub fixture {
    open my $f,'<:raw',"$FindBin::Bin/fixtures/$_[0].json" or die $!;
    local $/;return decode_json(<$f>);
}
sub clone {decode_json(encode_json($_[0]))}
sub deliver {
    my ($data,$error,$code)=@_;
    my $req=shift @queue or die 'no queued request';
    $req->{code}=$code//200;
    $req->{callback}->($req,$error//'',encode_json($data//{}));
    return $req->{url};
}
my $class='FHEM::APIs::Weather::GeoSphereAPI';
$attr{global}={latitude=>48.2486,longitude=>16.3564};
$defs{test}={NAME=>'test',TYPE=>'Weather',DEF=>'API=GeoSphereAPI'};
my $api=$class->new({devName=>'test',location=>'1,2',language=>'de'});
$defs{test}{fhem}{api}=$api;
$attr{test}{forecast}='hourly,daily';
is($api->{lat},48.2486,'global latitude overrides resolved fallback');
is($api->{long},16.3564,'global longitude');
is($api->{locationSource},'global','global source visible');
$defs{test}{DEF}='API=GeoSphereAPI location=47.1,13.2';
$api->_sync_location;
is($api->{lat},47.1,'explicit device latitude overrides global');
is($api->{long},13.2,'explicit device longitude overrides global');
is($api->{locationSource},'device','device source visible');
$defs{test}{DEF}='API=GeoSphereAPI';$api->_sync_location;
my $metadata=fixture('stations');
my $stations=$api->_station_list($metadata);
ok(@$stations>200,'active stations from official metadata');
ok($api->_distance($stations->[0]) <= $api->_distance($stations->[1]),'nearest stations first');
$attr{test}{userattr}='custom:one,two geoSphereStation:obsolete';
$attr{test}{geoSphereStation}='auto';
$api->_station_dropdown($stations);
like($attr{test}{userattr},qr/custom:one,two/,'unrelated user attribute preserved');
unlike($attr{test}{userattr},qr/obsolete/,'old dropdown replaced');
like($defs{test}{'.AttrList'},qr/WIEN_HOHE_WARTE__11035__0\.0km/,'internal station dropdown has name id and distance');
like($defs{test}{'.AttrList'},qr/forecast alerts disable/,'Weather base attributes preserved');
unlike($attr{test}{userattr},qr/geoSphereStation/,'no generated dropdown in userattr');
is($attr{test}{geoSphereStation},'auto','selected value preserved');
my $decl=$defs{test}{'.AttrList'}; $api->_station_dropdown($stations);
is($defs{test}{'.AttrList'},$decl,'dropdown update idempotent');
$attr{test}{userattr}.=' WIEN_MARIABRUNN__11080__6.6km,WIEN-DONAUFELD__11090__9.5km';
$api->_station_dropdown($stations);
is($attr{test}{userattr},'custom:one,two','orphan station-list fragments removed');

my $current=fixture('current');my $forecast=fixture('forecast');
my $base=FHEM::APIs::Weather::GeoSphereAPI::_epoch($current->{timestamps}[0]);
my $delta=time-$base-120;
for my $data ($current,$forecast) {
    $data->{timestamps}=[map {strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($_)+$delta))} @{$data->{timestamps}}];
    $data->{reference_time}=strftime('%Y-%m-%dT%H:%M:%SZ',gmtime(FHEM::APIs::Weather::GeoSphereAPI::_epoch($data->{reference_time})+$delta)) if $data->{reference_time};
}
# Initial auto mode: metadata -> multi-station probe -> selected station -> model.
$api->setRetrieveData;
like($queue[0]{url},qr{/metadata$},'metadata requested on first retrieval');
deliver($metadata);
like($queue[0]{url},qr/station_ids=\d+,/,'nearby stations probed in one request');
my @candidates=@$stations[0..7];
my $probe=clone($current);
$probe->{features}=[];
for my $i (0..$#candidates) {
    my $feature=clone($current->{features}[0]);
    $feature->{properties}{station}=$candidates[$i]{id};
    $feature->{properties}{parameters}{PRED}{data}[0]=undef if $i==0;
    push @{$probe->{features}},$feature;
}
deliver($probe);
is($api->{station},$candidates[1]{id},'nearest station with missing pressure skipped');
my $selected=clone($current);$selected->{features}[0]{properties}{station}=$api->{station};
deliver($selected);deliver($forecast);
is($api->getWeather->{status},'ok','auto selection publishes weather');
is($api->getWeather->{warningsStatus},'disabled','warnings disabled explicitly');
is($api->getWeather->{stationName},$candidates[1]{name},'station name exposed');
$api->{fetchTime}=0;$api->setRetrieveData;
like($queue[0]{url},qr/station_ids=$api->{station}$/,'selected auto station remains fixed');
deliver($selected);
is(scalar @queue,0,'model cache used without another probe');

# An explicit dropdown selection wins over auto/API configuration.
$attr{test}{geoSphereStation}='WIEN_HOHE_WARTE__11035__4.3km';
$api->_sync_station;is($api->{station},11035,'manual dropdown selection');
is($api->{fetchTime},0,'station change invalidates result cache');
ok(!$api->{model},'station change invalidates model snapshot');
$attr{test}{geoSphereStation}='invalid';eval {$api->_sync_station};like($@,qr/invalid geoSphereStation/,'invalid station selection rejected');
$attr{test}{geoSphereStation}='11035';$api->_sync_station;

# Warn-API payload parsing: real official example, independent of fixture age.
my $example=fixture('warnings-example');
my $empty=fixture('warnings-none');
my $exampleNow=1679896800+60;
my $parsed=$api->_warnings_parse($example,$exampleNow);
is(@{$parsed->{alerts}},2,'official example contains active and future warnings');
is($parsed->{alerts}[0]{phase},'active','active warning classified');
is($parsed->{alerts}[1]{phase},'upcoming','upcoming warning retained');
is($parsed->{alerts}[0]{severity},1,'official yellow severity');
is($parsed->{alerts}[0]{Event},'Wind','official warning type mapped');
is(@{$api->_warnings_parse($example,2000000000)->{alerts}},0,'expired warnings removed');
is(@{$api->_warnings_parse($empty,time)->{alerts}},0,'successful empty response accepted');
eval {$api->_warnings_parse({},time)};like($@,qr/invalid warnings/,'malformed response is not no-warnings');
my $bad=clone($example);$bad->{properties}{warnings}[0]{properties}{warnstufeid}=9;
eval {$api->_warnings_parse($bad,$exampleNow)};like($@,qr/severity/,'unknown severity rejected');
my $iso=clone($example);
$iso->{properties}{warnings}[0]{properties}{begin}='2023-03-27T08:00:00+02:00';
$iso->{properties}{warnings}[0]{properties}{end}='2023-03-27T18:00:00+02:00';
is($api->_warnings_parse($iso,$exampleNow)->{alerts}[0]{startEpoch},1679896800,'ISO warning time has correct offset');

# Enable alerts: warnings use device coordinates, never station coordinates.
$attr{test}{alerts}=1;$api->{metadataDone}=1;
$api->setRetrieveData;deliver($current);deliver($forecast);
like($queue[0]{url},qr/getWarningsForCoords\?lat=48\.2486&lon=16\.3564/,'warnings queried for device location');
deliver($empty);
is($api->getWeather->{warningsStatus},'ok','successful warnings retrieval');
is($api->getWeather->{warningsCount},0,'zero only after successful empty retrieval');
is($api->getWeather->{warningsArea},'Wien-Ottakring','warning area exposed');
$api->{fetchTime}=0;$api->{warningsFetched}=0;
$api->setRetrieveData;deliver($current);deliver({},'timeout');
is($api->getWeather->{status},'ok','warning timeout does not discard valid weather');
is($api->getWeather->{warningsStatus},'error','warning timeout has separate error status');
is($api->getWeather->{warningsCount},'unknown','warning error is not zero warnings');
is($defs{test}{READINGS}{warnCount}{VAL},'unknown','standard warnCount also unknown on failure');

# Location change clears warnings immediately and rejects late old responses.
$api->setRetrieveData;my $late=shift @queue;
$defs{test}{DEF}='API=GeoSphereAPI location=47.9,13.7';
$api->_sync_location;
ok(!$api->{warningsData},'warnings from previous location removed');
ok(!$api->{selectedAuto},'auto selection cleared on location change');
my $before=$notifications;
$late->{callback}->($late,'timeout','');
is($notifications,$before,'late response from old location ignored');

# FHEM uses UTF-8 byte strings; exactly one encoding pass is required.
my $wire=FHEM::APIs::Weather::GeoSphereAPI::_wire({text=>'Stark bewölkt'});
ok(!utf8::is_utf8($wire->{text}),'FHEM-facing string is byte encoded');
is(decode_utf8($wire->{text}),'Stark bewölkt','umlaut round trip');
is(FHEM::APIs::Weather::GeoSphereAPI::_wire($wire)->{text},$wire->{text},'no double encoding');
my $fc=$api->_forecast($forecast,time);
for my $day (@{$fc->{daily}}) {
    my ($code,$condition)=$api->_symbol_condition($day->{geoSphereSymbol});
    is($day->{condition},$condition,'daily condition matches official representative symbol');
    like($day->{conditionSource},qr/representative hour/,'single-hour origin explicitly disclosed');
}
done_testing;
