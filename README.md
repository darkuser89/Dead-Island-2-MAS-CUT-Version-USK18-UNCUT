# Dead Island 2 Uncut Launcher

Externer macOS-Launcher für die App-Store-Version von **Dead Island 2**. Er
beeinflusst ausgewählte Identitätsabfragen zur Laufzeit und erhält die
unveränderte Hersteller-App mit ihren ursprünglichen CloudKit-Berechtigungen.

**Version 1.0 · Apple Silicon · GPL-3.0-only**

## Voraussetzungen

- Ein Mac mit Apple Silicon (`arm64`).
- Xcode oder Xcode Command Line Tools mit macOS-SDK und Clang.
- Python 3 für Pfad-, Prozess- und Installationsprüfungen.
- Für die Nutzung: die unveränderte **USK-App-Store-Version** unter
  `/Applications/DeadIsland2.app`, Bundle-ID `com.plaion.DeadIsland2Usk`.

Das Deployment-Ziel ist macOS 14.0. Das ist keine vollständige Zusage für jede
macOS- oder Spielversion. App-Updates können die benötigten Berechtigungen oder
das Laufzeitverhalten ändern. Intel-Macs und die Steam-Version sind keine Ziele
dieses Launchers.

## Bauen

Im Projektverzeichnis:

```sh
./script/build.sh
```

Der Befehl kompiliert den Launcher und das Hilfsmodul, führt den isolierten
Laufzeittest aus und prüft die lokale Signatur. Er installiert und startet kein
Spiel. Der Build funktioniert ohne Spielinstallation und ohne Entwicklerkonto.

Standardausgabe:

```text
~/Library/Developer/DeadIsland2UncutLauncher/Dead Island 2 Uncut.app
```

Ein anderer, **außerhalb des Quellcodeordners** liegender Buildordner lässt sich
über `DI2_BUILD_DIR` festlegen. Verwende denselben Wert beim Bauen und Installieren:

```sh
export DI2_BUILD_DIR="$HOME/Library/Developer/DeadIsland2UncutLauncher"
./script/build.sh
```

Optionen:

```sh
./script/build.sh --validate-game   # zusätzlich Originalsignatur und App-ID prüfen
./script/build.sh --with-game-icon  # Icon aus der lokalen Spielinstallation übernehmen
./script/build.sh --help
```

Ohne `--with-game-icon` wird kein Spiel-Asset eingebunden. Das Repository enthält
keine Spiel-Dateien, Spiel-Icons, Zertifikate oder privaten Signierschlüssel.

## Installieren und starten

Beende das Spiel und einen laufenden Starthelfer regulär. Dann:

```sh
./script/install.sh
open "/Applications/Dead Island 2 Uncut.app"
```

Eine vorhandene, gültig signierte Launcher-Installation kann bewusst ersetzt werden:

```sh
./script/install.sh --replace
```

Der Installer verschiebt den geprüften Build nach `/Applications`. Für den
Austausch werden Build und Ziel auf demselben Dateisystem benötigt. Andere Apps
werden nicht ersetzt. Ein fehlgeschlagener Austausch wird zurückgenommen;
scheitert auch die Rücknahme, bleibt die vorherige App zur Wiederherstellung erhalten.
Die Installation selbst startet kein Spiel.

Der Launcher startet ausschließlich die App-Store-App unter
`/Applications/DeadIsland2.app`. Eine bereits laufende Spielinstanz wird nicht
automatisch beendet. Für einen Uncut-Start den Starthelfer verwenden.

Für die lokale Entwicklung gibt es weiterhin den kombinierten Einstieg:

```sh
./script/build_and_run.sh --build-only  # nur bauen und testen
./script/build_and_run.sh              # bauen, Launcher ersetzen und starten
```

## Funktionsweise

1. Der Launcher prüft die Apple-Code-Signatur, die originale USK-App-ID und die
   signierte Hersteller-Teamkennung.
2. Er startet das Originalspiel über `NSWorkspace`. `DYLD_INSERT_LIBRARIES` wird
   ausschließlich in der Umgebung dieses neuen Spielprozesses gesetzt.
3. Das externe Modul ersetzt drei `NSBundle`-Abfragen. Nur Aufrufe aus dem
   ausführbaren Hauptprogramm erhalten die Laufzeitkennung
   `com.plaion.DeadIsland2` und den vorbereiteten `USKVersion`-Wert.
4. Aufrufe aus anderen Mach-O-Images erhalten die Originalwerte. Andere Bundles
   werden ebenfalls nicht umgestellt.

Der Ansatz verwendet die bereits in der Original-App vorhandenen Berechtigungen
für externe Bibliotheken. Die Spiele-App wird nicht kopiert, gepatcht oder neu
signiert. Es werden keine globalen DYLD-Einstellungen gesetzt und keine
macOS-Sicherheitseinstellungen geändert. Die Steam-Installation wird nicht geöffnet
oder verändert.

Die Pfad- und Signaturprüfungen sind auf die originale App-Store-USK-Fassung
begrenzt. Die Vorprüfung validiert Code und signierte Metadaten; sie führt beim
Start keinen vollständigen Inhaltsvergleich sämtlicher großer Spielpakete durch.

## iCloud und Diagnose

Die echte signierte App-Identität und die CloudKit-Berechtigungen bleiben erhalten.
Das Spiel verwendet weiterhin seinen ursprünglichen CloudKit-Container.
Ein vorhandener CloudKit-Zugang allein beweist noch keinen erfolgreichen
Spielstand-Abgleich zwischen zwei Geräten.

Zusätzliche CloudKit-Diagnosen sind im Quellcode standardmäßig ausgeschaltet.
Bei Bedarf kann der Launcher mit einem einmaligen lesenden Test gestartet werden:

```sh
open -n --env DI2_LAUNCHER_CLOUD_CHECK=1 "/Applications/Dead Island 2 Uncut.app"
```

Dieser Test prüft Kontostatus und Erreichbarkeit der privaten Datenbank. Er
fordert keine Cloud-Schreiboperation an und protokolliert keine Spielstände
oder Datensatzinhalte. Das Spiel selbst kann seine reguläre Cloud-Speicherung nutzen.

Lokale Diagnosemeldungen anzeigen:

```sh
log show --last 10m --style compact \
  --predicate 'subsystem == "local.deadisland2.launcher"'
```

Bei einer fehlenden Originalsignatur, ungeeigneter App-ID oder fehlenden
Laufzeitberechtigungen muss die Ursache zuerst geprüft werden. Das Buildskript
verändert dafür weder die Spielsignatur noch Systemschutzfunktionen.

## Tests und Grenzen

Der Build prüft mit einem kleinen, separat erzeugten Programm und einer zweiten
Bibliothek:

- die Umstellung von Abfragen aus dem ausführbaren Hauptprogramm;
- unveränderte Werte für Aufrufe aus einem anderen Mach-O-Image;
- unveränderte Werte für andere Bundles;
- die Begrenzung des zusätzlichen SKU-Werts auf die Spielseite;
- die unveränderte `Info.plist` auf dem Datenträger;
- die Signatur des gebauten Launchers.

Die CI baut auf einem macOS-ARM64-Runner. Sie startet das Spiel nicht und prüft
weder Uncut im Gameplay noch eine tatsächliche iCloud-Synchronisierung.
Diese Punkte müssen nach relevanten Änderungen mit der eigenen Spielinstallation
geprüft werden. Koop, andere Spielversionen und andere macOS-Versionen sind
gesondert zu prüfen.

## Projektstruktur

```text
Sources/      Launcher und Laufzeitmodul
Tests/        Isolierter Image-Grenztest
Resources/    Eigene App-Metadaten
script/       Build, Installation und lokaler Start
.github/      Build-Workflow
LICENSE       Vollständiger GPL-3.0-Lizenztext
```

Builds, Apps, Objektdateien, Logs und lokale Editor-Metadaten werden nicht in Git
aufgenommen. Das Spiel-Icon wird ausschließlich auf ausdrückliche Build-Option
aus der lokalen Original-App gelesen.

## Lizenz

Copyright © 2026 darkuser89. Der Launcher-Code steht unter **GNU GPL Version 3**
(`GPL-3.0-only`). Der vollständige Text steht in [LICENSE](LICENSE).

Dead Island 2 und die zugehörigen Spiel-Assets gehören ihren jeweiligen
Rechteinhabern. Dieses unabhängige Projekt enthält diese Assets nicht und ist
kein offizielles Produkt von PLAION, Deep Silver oder Apple.
