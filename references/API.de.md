# API-Beschreibung

Dieses Dokument beschreibt exemplarisch den Aufbau und die benötigten Rahmenbedingungen eines API Modules für 59_Weather.pm

Da sich die API selbst noch in Entwicklung befindet, sollte vor jedem neuen API-Module ein Blick in dieses Dokument geworfen werden.

## Genereller Aufbau des API-Modules

Das Modul muss zwingend Objektorientiert geschrieben werden. Man sollte sich also schon einmal damit befasst haben um zu verstehen, wie so ein objektorientiertes Modul funktioniert.

Alle API Moduldateien für 59_Weather.pm werden unter `lib/FHEM/APIs/Weather/` abgelegt

Der Packagename muß im Format `FHEM::APIs::Weather<SERIVCE_NAME>API` angegeben werden, also z.B.

    package FHEM::APIs::Weather::FoobarAPI
    
für den Wetter-Service Foobar.

## Das Modul

### Konstruktor

59_Weather ruft den Konstuktor des API-Moduls wie folgt auf:

    FoobarAPI::Weather->new(
        { 
            devName => $hash->{NAME}, 
            apikey => $hash->{APIKEY}, 
            location => $hash->{LOCATION}, 
            apioptions => $hash->{APIOPTIONS}, 
            language => $hash->{LANG} 
        } 
    );
    
Beim Aufruf des Konstruktors wird diesem ein Hash mitübergeben, welcher Listenelemente beinhaltet. (Hash mit Skalaren).

Jedes Listenelement besteht aus einem Schlüssel und einem Wert. Der Schlüssel muß nicht zwingend in direkter Verbindung zur Bedeutung des Wertes stehen. Der `APIKEY` kann zum Beispiel auch eine Zeichenkette aus der Kombination `Nutzername:Passwort` sein, oder auch ein OAuth-Token. Je nachdem was zum Bezug der Daten vom Anbieter benötigt wird.

`LOCATION` kann, muss aber nicht, im Format `Latitude,Longitude` angegeben werden, sondern kann auch eine Stations-ID sein. Nur der `devName` muss unbedingt korrekt übergeben und später an die `CallbackFn` zurück gegeben werden.

Wird `LOCATION` und `LANGUAGE` beim Define des Devices nicht angeben, wird von `Weather` versucht, diese aus dem `global`-Device zu erhalten.

#### Beispiel

    sub new {
        ### geliefert wird ein Hash
        my ( $class, $argsRef ) = @_;
    
        my $self = {
            devName => $argsRef->{devName},
            key     => $argsRef->{$apikey},
            cachemaxage => (
                ( defined( $argsRef->{apioptions} ) and $argsRef->{apioptions} )
                ? (
                      ( split( ':', $argsRef->{apioptions} ) )[0] eq 'cachemaxage'
                    ? ( split( ':', $argsRef->{apioptions} ) )[1]
                    : 900
                  )
                : 900
            ),
            lang      => $argsRef->{language},
            lat       => ( split( ',', $argsRef->{location} ) )[0],
            long      => ( split( ',', $argsRef->{location} ) )[1],
            fetchTime => 0,
        };
    
        bless $self, $class;
        return $self;
    }

### Verpflichtende Objektmethoden

Es müssen zwingend zwei Objektmethoden vorhanden sein. `Weather` wird dann über den Konstruktor eine neue Instanz als Instanzvariable anlegen. Über diese Instanzvariablen werden dann die zwei Methodenaufrufe durchgeführt.

`$obj->setRetrieveData` wird in `Weather` in der GetUpdate-Funktion aufgerufen.

`$obj->getWeather` wird in der `CallbackFn-Funktion aufgerufen um die Daten aus dem API-Modul zu erhalten. Vorher muss aus dem API-Modul heraus die `CallbackFn` aufgerufen und der Name der `Weather`-Instanz übergeben werden: `Weather_CallbackFn(devName);`

Für beide Methodenaufrufe **muss** eine entsprechende Methode existieren. Das ist Pflicht.

### Aufbau der Response des API-Moduls

Zwingend als Reading müssen folgende Werte geliefert werden, da diese gesondert behandelt werden:

* `status` (Hash)
* `apiMaintainer` (Hash)
* `apiVersion` (Hash)
* `{license}->{text}` (Hash in Hash)
* `{license}->{text}` (Hash in Hash)
* `{current}->{code}` (Hash in Hash)
* `{current}->{wind_direction}` (Hash in Hash)
* `{current}->{wind_speed}` (Hash in Hash)
* `{current}->{temperature}` (Hash in Hash)
* `{current}->pressure}` (Hash in Hash)
* `{current}->{wind}` (Hash in Hash)
* `{current}->{humidity}` (Hash in Hash)

Als Reading empfohlen, da historisch vorhanden und in der Weblink-Ansicht vorhanden:

* day_of_week (Hash aus forecast)
* icon (Hash)
* condition (Hash)
* temp_c
* humidity
* low_c
* high_c

#### Beispiel erfolgreiche Datenübertragung

    $response = (
            {
         status => 'ok',
         validity => 'up-to-date',
                 lat  => latitude,
                 long => longitude,
                 apiMaintainer => 'Maintainer Info',
         apiVersion => '2.0.3',
         current_date_time => am besten die fetchtime,
                 timezone = timezone der Responsedaten,
                 license => {
                                text => 'Lizenz vom Anbieter',
                    },
                 current => {
                temperature => temperatur vom Anbieter,
                temp_c => temperatur vom Anbieter,
                humidity => Luftfeuchte vom Anbieter,
                condition => Wetterbeschreibung vom Anbieter,
        },
        forecast => {
                daily => [	
                        {
                            temperature => temperatur vom Anbieter,
                            temp_c => temperatur vom Anbieter,
                            low_c => niedrigste Temperatur,
                            high_c => höchste Temperatur,
                        },
                        {
                            temperature => temperatur vom Anbieter,
                            temp_c => temperatur vom Anbieter,
                            low_c => niedrigste Temperatur,
                            high_c => höchste Temperatur,
                        },
                        {
                            temperature => temperatur vom Anbieter,
                            temp_c => temperatur vom Anbieter,
                            low_c => niedrigste Temperatur,
                            high_c => höchste Temperatur,
                        },
                ],
                hourly => [
                        {
                            temperature => temperatur vom Anbieter,
                            temp_c => temperatur vom Anbieter,
                            low_c => niedrigste Temperatur,
                            high_c => höchste Temperatur,
                        },
                        {
                            temperature => temperatur vom Anbieter,
                            temp_c => temperatur vom Anbieter,
                            low_c => niedrigste Temperatur,
                            high_c => höchste Temperatur,
                        },
                        {
                            temperature => temperatur vom Anbieter,
                            temp_c => temperatur vom Anbieter,
                            low_c => niedrigste Temperatur,
                            high_c => höchste Temperatur,
                        },
                ],
            },
        );

#### Beispiel einer fehlerhaften Datenübertragung

    $hash = (
        {
            status => $error,
            validity => 'stale',
            lat  => latitude,
            long => longitude,
            apiMaintainer => 'Maintainer Info',
            current_date_time => x                  # Die letzte fetchtime einer erfolgreichen Datenabfrage,
            license => {
                text => 'Lizenz vom Anbieter',
            },
        },
    );

Sobald alle Daten fertig verarbeitet wurden und zur Abholung bereit sind, kann das API-Modul die `CallbackFn` von `Weather` aufrufen.

    main::Weather_RetrieveCallbackFn( $self->{devName} );
    
Diese Callback-Funktion holt sich dann über den Methodenaufruf `getWeather` die Datenstruktur `$obj->getWeather` und verarbeitet diese in Readings.

#### Yahoo-API
Für das Reading `code` sollte ein Mapping auf die Yahoo-Codes innerhalb des API-Modules stattfinden. Diese findet man in der [Dokumentation der Yahoo API](https://developer.yahoo.com/weather/documentation.html#codes).