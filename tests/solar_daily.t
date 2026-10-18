#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP qw(decode_json encode_json);
use POSIX qw(strftime tzset);
use Time::Local qw(timelocal);
use FHEM::APIs::Weather::GeoSphereAPI;

$ENV{TZ}='Europe/Vienna'; tzset();
my $class='FHEM::APIs::Weather::GeoSphereAPI';
my $api=$class->new({devName=>'solar',location=>'48.2486,16.3564',apioptions=>'station:11035'});
sub fixture {open my $f,'<:raw',"$FindBin::Bin/fixtures/$_[0].json" or die $!;local $/;decode_json(<$f>)}
sub clone {decode_json(encode_json($_[0]))}
sub iso {strftime('%Y-%m-%dT%H:%M:%SZ',gmtime($_[0]))}
sub epoch {$class->can('_epoch')->($_[0])}
$api->_sync_station;
my $current=fixture('current');
my $p=$current->{features}[0]{properties}{parameters};
$p->{TP}={unit=>'°C',data=>[8.7]};
$p->{GLOW}={unit=>'W/m²',data=>[279]};
$p->{SO}={unit=>'sec',data=>[432]};
my $now=epoch($current->{timestamps}[0])+60;
my $observed=$api->_current($current,$now)->{readings};
is($observed->{dewPoint},8.7,'observed dew point taken from station TP');
is($observed->{dewPointSource},'GeoSphere station TP','observed source identified');
is($observed->{globalRadiation},279,'station radiation retained in W/m2');
is($observed->{sunshineDuration_s},432,'station sunshine duration in seconds');
is(epoch($observed->{sunshinePeriodEnd})-epoch($observed->{sunshinePeriodStart}),600,'station sunshine interval ten minutes');
for my $case (['TP',undef,'dewPoint'],['TP',99,'dewPoint'],['GLOW',undef,'globalRadiation'],['GLOW',-1,'globalRadiation'],['SO',undef,'sunshineDuration_s'],['SO',601,'sunshineDuration_s']) {
    my ($parameter,$value,$reading)=@$case;
    my $copy=clone($current);$copy->{features}[0]{properties}{parameters}{$parameter}{data}[0]=$value;
    is($api->_current($copy,$now)->{readings}{$reading},'',"missing/impossible $parameter not invented");
}
for my $pair (['GLOW','globalRadiation'],['SO','sunshineDuration_s']) {
    my $copy=clone($current);$copy->{features}[0]{properties}{parameters}{$pair->[0]}{data}[0]=0;
    is($api->_current($copy,$now)->{readings}{$pair->[1]},0,"zero $pair->[0] is valid");
}
my $legacy=fixture('current');
is($api->_current($legacy,$now)->{readings}{temperature},13.2,'optional missing fields preserve core observations');
for my $reading (qw(dewPoint globalRadiation sunshineDuration_s)) {
    is($api->_current($legacy,$now)->{readings}{$reading},'',"unavailable $reading empty");
}
is($class->can('_dew_point')->(20,50),9.3,'calculated dew point at 20C/50% is about 9.3C');
is($class->can('_dew_point')->(20,100),20,'saturated dew point equals air temperature');
is($class->can('_dew_point')->(20,0),'','zero RH has no finite dew point');

sub model {
    my ($start,$steps)=@_;
    my $data=fixture('forecast');
    $data->{reference_time}=iso($start-1800);
    $data->{timestamps}=[map {iso($start+$_*3600)} 0..$steps];
    my $params=$data->{features}[0]{properties}{parameters};
    for my $key (keys %$params) {$params->{$key}{data}=[($params->{$key}{data}[0])x($steps+1)]}
    for my $spec (['2t','degree Celsius',20],['2r','%',50],['tp','kg m-2',1],['rain','kg m-2',0.25],['sf','kg m-2',0.75],['ssrd','W m-2',250],['sund','s',1800]) {
        $params->{$spec->[0]}={unit=>$spec->[1],data=>[($spec->[2])x($steps+1)]};
    }
    return $data;
}
my $start=timelocal(0,0,0,18,9,2026);
my $data=model($start,29);
# The interval ending at today's 00:00 belongs to yesterday and must be excluded.
$data->{features}[0]{properties}{parameters}{tp}{data}[0]=999;
my $forecast=$api->_forecast($data,$start);
my $hour=$forecast->{hourly}[0];my $day=$forecast->{daily}[0];
is($hour->{dewPoint},9.3,'forecast dew point derived from temperature and humidity');
like($hour->{dewPointSource},qr/calculated/,'derived dew point not presented as observation');
is($hour->{globalRadiation},250,'NWP global radiation read');
is($hour->{sunshineDuration_s},1800,'NWP sunshine duration read');
is(epoch($hour->{sunshinePeriodEnd})-epoch($hour->{sunshinePeriodStart}),3600,'NWP sunshine interval one hour');
is($day->{precipitation},24,'daily total excludes prior-day midnight interval and includes following midnight');
is($day->{rainTotal_mm},6,'daily liquid rain independently accumulated');
is($day->{snowWaterEquivalent},18,'daily snow water equivalent accumulated');
is($day->{sunshineDuration_s},43200,'daily sunshine seconds accumulated');
is($day->{rain1h},'','daily row does not pretend total is one-hour rain');
for my $field (qw(precipitationCoverage rainCoverage snowCoverage sunshineCoverage)) {is($day->{$field},'complete',"complete daily $field")}
is($day->{precipitationSamples},24,'daily precipitation sample count');
is($day->{precipitationExpectedSamples},24,'normal day expects 24 intervals');
is(epoch($day->{precipitationPeriodStart}),$start,'daily accumulation starts local midnight');
is(epoch($day->{precipitationPeriodEnd}),$start+86400,'daily accumulation ends next local midnight');
is($day->{precipitationHours},24,'wet-hour count uses accumulation intervals');
is($day->{snowfallHours},24,'snow-hour count uses accumulation intervals');
like($day->{summaryCondition},qr/Niederschlagsstunden: 24/,'daily summary exposes wet-hour occurrence');
like($day->{conditionSource},qr/official GeoSphere sy; representative hour/,'existing official icon semantics retained');

for my $case (['tp','precipitation','precipitationCoverage'],['rain','rainTotal_mm','rainCoverage'],['sf','snowWaterEquivalent','snowCoverage'],['sund','sunshineDuration_s','sunshineCoverage']) {
    my $copy=clone($data);$copy->{features}[0]{properties}{parameters}{$case->[0]}{data}[5]=undef;
    my $daily=$api->_forecast($copy,$start)->{daily}[0];
    is($daily->{$case->[1]},'',"missing $case->[0] prevents fabricated daily sum");
    is($daily->{$case->[2]},'unknown',"missing $case->[0] validity explicit");
    if ($case->[0] eq 'tp') {
        is($daily->{rainTotal_mm},6,'missing total leaves complete liquid rain usable');
        is($daily->{precipitationHours},'','unknown rain amount cannot confirm dry-hour count');
        like($daily->{summaryCondition},qr/Niederschlagsstunden: unbekannt/,'summary discloses missing data');
    }
}
my $partial=$api->_forecast(model($start,12),$start)->{daily}[0];
is($partial->{precipitation},12,'partial amount counts only covered intervals');
is($partial->{precipitationCoverage},'partial','partial amount not called full daily total');
is($partial->{sunshineCoverage},'partial','partial sunshine scope explicit');
my $offset=$api->_forecast(model($start+1800,29),$start)->{daily}[0];
is($offset->{precipitation},23,'off-grid boundary intervals outside the local day excluded');
ok(epoch($offset->{precipitationPeriodStart}) >= $start,'all summed intervals start inside the local day');
ok(epoch($offset->{precipitationPeriodEnd}) <= $start+86400,'all summed intervals end inside the local day');
my $missing=clone($data);delete $missing->{features}[0]{properties}{parameters}{ssrd};delete $missing->{features}[0]{properties}{parameters}{sund};
my $optional=$api->_forecast($missing,$start);
is($optional->{hourly}[0]{globalRadiation},'','missing ssrd remains empty');
is($optional->{daily}[0]{sunshineCoverage},'unknown','missing sund not zero sunshine');
for my $case (['2026-03-29',23],['2026-10-25',25]) {
    my ($year,$month,$d)=split /-/,$case->[0];
    my $midnight=timelocal(0,0,0,$d,$month-1,$year);
    my $dst=$api->_forecast(model($midnight,$case->[1]+5),$midnight)->{daily}[0];
    is($dst->{precipitation},$case->[1],"$case->[0] counts actual DST intervals");
    is($dst->{precipitationExpectedSamples},$case->[1],'DST expected count correct');
    is($dst->{precipitationCoverage},'complete','DST amount complete');
    is(epoch($dst->{precipitationPeriodEnd})-epoch($dst->{precipitationPeriodStart}),$case->[1]*3600,'DST civil day interval length correct');
}
my $result={current=>$observed,forecast=>$forecast};$api->_localize_result($result);
for my $value ($observed->{sunshinePeriodStart},$observed->{sunshinePeriodEnd},$hour->{sunshinePeriodStart},$day->{sunshinePeriodEnd}) {
    like($value,qr/ CEST$/,'new visible sunshine boundary uses local time');
}
my $wire=$class->can('_wire')->($result);
ok(!utf8::is_utf8($wire->{current}{globalRadiationUnit}),'radiation unit encoded for FHEM');
done_testing;
