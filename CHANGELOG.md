# Changelog

## 0.2.13 – 2026-10-28 – beta, API-only

- Return `GeoSphereNowcastAsHtml` as UTF-8 octets at the FHEMWEB boundary,
  preventing double encoding of degree signs in adjacent Weather HTML.
- Decode UTF-8 reading octets before HTML escaping and retain a safe fallback
  for malformed input.
- Keep nowcast values and the `mm/15 min` interval unit unchanged.

## 0.2.12 – 2026-10-28 – beta, API-only

- Add optional `GeoSphereNowcastAsHtml` FHEMWEB rendering for the
  provider-specific 15-minute precipitation intervals.
- Limit rendered bars by both the requested maximum and `nowcastPoints`;
  distinguish the running quarter hour and show validity/reference details.
- Document copy-ready hourly, daily and nowcast weblinks.
- Keep the Weather core and device configuration unchanged.

## 0.2.11 – 2026-10-28 – beta, API-only

- Format hourly `day_of_week` as localized abbreviated weekday plus
  `HH:MM`, matching established Weather providers and keeping
  `WeatherAsHtml*` output compact.
- Keep full timestamps in `timestamp`, `pubDate`, observations, nowcast,
  warnings and diagnostics.
- Add a Weather-core contract assertion for the compact hourly label.
- No Weather-core change or configuration migration required.

## 0.2.10 – 2026-10-22 – beta, API-only

- Catch invalid location, altitude, station, API-option and timeout configuration
  at the provider boundary instead of terminating the FHEM process.
- Publish constructor errors immediately through `state`, `status` and
  `lastError`; retain revalidation on later updates so corrected dynamic
  settings can recover normally.
- Add regression coverage with the unmodified FHEM Weather core.

## 0.2.9 – 2026-10-20 – beta, API-only

- Stop publishing empty `wind_condition` values for current observations and
  hourly forecasts, preventing DbLog warnings while parsing empty Weather events.
- Keep the normal localized wind description in the unmodified Weather core.
  Add a complete provider fallback for 0-degree north wind, calm wind and
  unavailable direction or speed values.
- Add focused regression tests. No Weather-core change and no configuration
  migration are required.

## 0.2.8 – 2026-10-18 – beta, API-only

- Set the maintainer to 50watt in API diagnostics, FHEM metadata and support documentation.
- No weather data processing or FHEM core changes.

## 0.2.7 – 2026-10-18 – beta, API-only

- Add observed dewPoint from station TP, globalRadiation from GLOW and sunshineDuration_s from SO. Keep unavailable optional observations empty and expose source, units and local sunshine interval boundaries.
- Add hourly globalRadiation from ssrd and sunshineDuration_s from sund. Derive and label an approximate forecast dewPoint from temperature/RH; do not represent it as an official GeoSphere dew-point parameter.
- Aggregate daily total precipitation, liquid rainTotal_mm, snow water equivalent and sunshine duration from full hourly intervals contained in each local calendar day. Handle 23/25-hour DST days and midnight attribution. Expose independent completeness/sample counts and actual accumulation boundaries; missing values are not zero.
- Add a separate derived summaryCondition with cloud classification and precipitation/snowfall-hour counts (threshold 0.1 mm). Existing official representative-hour condition/icon behavior remains compatible.
- Remove Weather patch, preparation tool and patched-core tests from this release. The installer changes only GeoSphereAPI.pm; no Weather/HomeMode core changes are required.
- Keep logging selection unchanged. Global radiation is not converted into PV production or an assumed daily energy yield. UV, apparent temperature and SYNOP integration are not introduced.

## 0.2.6 – 2026-10-18 – beta

- Revalidate forecast age on observation failure; remove expired forecast records on the error path instead of claiming up-to-date model data.
- Check provider object identity before all asynchronous callbacks and attribute registration. Ignore responses for deleted/redefined devices.
- Preserve calendar slots for HomeMode at midnight: an unavailable today has coverage=missing and empty extrema; tomorrow remains fc2, including DST boundaries.
- Honour disabled Weather forecasts: skip the NWP request while retaining observations, warnings and optional nowcast.
- Add hourly rain1h from the explicit liquid rain parameter. Keep precipitation as total liquid/solid water equivalent, expose local interval boundaries, and never alias total precipitation to liquid rain.
- Add META.json/FHEM metadata registration, support information and consistent Perl::Tidy formatting. Isolate attribute registration in an identity-checked FHEM adapter; migrate legacy userattr through FHEM commands instead of writing its hash directly.
- Keep temporary setLocation coordinates across updates; changed DEF supersedes them. Provide a separate minimal Weather newLocation review patch and a guarded candidate-only preparation tool. The normal installer does not modify Weather core or configuration.
- Refresh documentation, logging examples, SVN submission instructions and regression coverage. No private coordinates or fabricated maintainer identity.

## 0.2.5 – 2026-10-18 – experimental

- Map official GeoSphere sy 1–32 to localized descriptions and existing FHEM Weather icons. Preserve raw codes and official English symbol names.
- Hourly official symbols take precedence over the cloud/precipitation approximation. Missing/unsupported symbols retain an explicitly marked fallback.
- Daily symbols describe the existing representative hour, explicitly disclosed by conditionSource and representativeTime; no claim of an official whole-day symbol.
- Current observations and apparent temperature remain unchanged. No extra HTTP request, dependency or configuration attribute.
- Regression checks include original Weather cores, UTF-8, official symbols conflicting with cloud cover, and fallback behavior.


## 0.2.4 – 2026-10-18 – experimental

- Optionaler 15-Minuten-Niederschlagsnowcast für die Gerätekoordinaten; `geoSphereNowcast` oder API-Option `nowcast`.
- Viertelstundenmengen, vierperiodige Regensumme, explizite Zeitfenster und eigener Gültigkeits-/Fehlerstatus; Fehler bedeuten unknown.
- Nicht mehr verfügbare Viertelstundenreadings werden entfernt; Standortwechsel verwirft alte Daten und verspätete Antworten.
- Alias und Kommentar im Konfigurationsbeispiel, Dokumentation der Niederschlagsintervalle und Cachegrenzen.
- Keine automatischen Konfigurationsänderungen, keine Umstellung vorhandener Regenautomationen.

## 0.2.3 – 2026-10-17 – experimental

- Format existing visible timestamp readings in local process time with CET/CEST
  instead of UTC/RFC-style mixed formats; retain numeric epochs and raw model data.
- Add human-readable forecastAge and DST transition tests.
- Increase default forecastmaxage to nine hours; retain future-coverage validation.
- Add targeted HomeMode setup and weather templates without unavailable apparent
  temperature or observed weather conditions. Configuration is never auto-applied.
- Document the intentional timestamp reading format change for custom consumers.

## 0.2.2 – 2026-10-17 – experimental

- Isolate forecast timeouts, HTTP/JSON/schema errors and stale model references
  from fresh station observations and the subsequent warnings retrieval.
- Expose forecastStatus, forecastValidity, forecastLastError and forecastAge_s.
- Remove unusable old forecast readings; recover them on a fresh model response.
- Keep the existing six-hour model age limit unchanged.
- Add 39 forecast-isolation checks and 12 additional assertions per Weather core.
- Station failures still use the existing overall Weather error path.

## 0.2.1 – 2026-10-17 – experimental

- Add altitude-aware automatic station ranking and explicit height provenance.
- Do not inherit home altitude for an unrelated device location.
- Reevaluate automatic selections after altitude changes and the 0.2.0 upgrade.
- Register provider attributes at construction and retain Weather's base AttrList.
- Keep station dropdown choices in runtime .AttrList, remove old generated userattr
  declarations and recognisable orphan list fragments without removing the selection.
- Add altitude, upgrade and Weather contract regression tests.
- Complete installation, troubleshooting, attribution and submission documentation.
- Replace private example/test coordinates with a documented public station location.
- Record the unsuccessful external live check caused by stale forecast data.

## 0.2.0 – 2026-10-17 – experimental

- Fix FHEM UTF-8 boundary and consistent daily weather descriptions.
- Add global/device location precedence, station metadata and manual/automatic selection.
- Add optional location-specific official GeoSphere warnings and separate error states.

## 0.1.0 – 2026-10-17 – prototype

- Initial standalone Weather provider: station observations and model forecasts.
