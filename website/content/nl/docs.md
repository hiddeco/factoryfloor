---
title: Docs
translationKey: docs
hideInstall: true
layout: docs
---

## Aan de slag {#getting-started}

We schrijven 2026. We bouwen op tmux (2007), Git-worktrees (2015), terminals (1978, het VT100-tijdperk, toen zelfs [David](https://davidpoblador.com) nog maar een toekomstproject was) en GPU-rendering (dank je [Mitchell](https://mitchellh.com) voor [Ghostty](https://ghostty.org)). Oude gereedschappen, nieuwe trucs.

Je hebt twee dingen nodig: een Mac en het vage gevoel dat je huidige workflow beter kan.

```
brew install --cask factory-floor
```

<a href="https://github.com/alltuner/factoryfloor/releases/latest/download/FactoryFloor.dmg" class="docs-download"><svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> DMG downloaden</a>

Factory Floor werkt het beste als deze tools geïnstalleerd zijn (de app vertelt je als er iets ontbreekt):

- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)** — het eigenlijke doel van dit alles
- **git** — heb je waarschijnlijk al
- **[gh](https://cli.github.com/)** — GitHub CLI, voor PR-status en snelacties
- **[tmux](https://github.com/tmux/tmux)** — optioneel, maakt sessiepersistentie mogelijk

#### Je eerste 30 seconden {#your-first-30-seconds}

1. Open Factory Floor
2. Sleep een git-repository naar de zijbalk (of klik **+** om er een te kiezen)
3. Druk op **⌘N** om een workstream aan te maken
4. Dat was het. Je programmeert nu met AI.

Geen configuratiebestanden nodig. Factory Floor detecteert je git-setup, geïnstalleerde tools en GitHub-koppelingen automatisch.

---

## Kernconcepten {#core-concepts}

De drie dingen waar je dagelijks mee werkt.

### Projecten {#projects}

Een project is een git-repository. Sleep een map naar de zijbalk of klik op de **+**-knop. Factory Floor controleert of het een git-repo is (en biedt aan er een te initialiseren als dat niet zo is).

Het projectoverzicht toont repository-info, GitHub-details (sterren, forks, open issues), tot 5 recente PR's en automatisch gedetecteerde markdown-documentatie uit je repo.

Projecten worden standaard gesorteerd op **Recent** (laatste activiteit). Schakel over naar **A-Z** als je zo'n type bent.

Klik met de rechtermuisknop op een project in de zijbalk voor snelle toegang: **Toon in Finder**, **Openen in externe terminal**, **Openen op GitHub** of **Verwijderen** (bestanden blijven op schijf, we zijn geen monsters).

### Workstreams {#workstreams}

Een workstream is waar het werk plaatsvindt. Elke workstream krijgt een eigen git worktree, branch, terminal, Coding Agent en browsertab. Ze zijn volledig van elkaar geïsoleerd.

**⌘N** maakt een nieuwe workstream aan. Achter de schermen:

1. Haalt de laatste default branch op van origin
2. Maakt een git worktree aan met een verse branch (met je branch-prefix, standaard: `ff`)
3. Linkt `.env` en `.env.local` vanuit de hoofdrepo (indien ingeschakeld)
4. Voert het setup-script uit (indien geconfigureerd)
5. Start de Coding Agent

De interface verschijnt meteen — het aanmaken van de worktree draait op de achtergrond.

#### Workstream-tabs {#workstream-tabs}

- **Info** — branch-naam, PR-status, projectdocumentatie
- **Agent** (⌘Return) — je Claude Code-sessie
- **Environment** — setup- en run-scriptbesturing
- **Terminal** (⌘T) — extra terminaltabs, zoveel als je wilt
- **Browser** (⌘B) — ingebouwde browser met automatische poortdetectie

#### Branch auto-rename {#branch-auto-rename}

Met **Auto-rename branch** ingeschakeld in de instellingen hernoemt de Coding Agent je branch bij de eerste prompt passend bij de taak. Zo wordt `ff/coral-tidal-reef` dan `ff/fix-login-timeout`.

#### Verwijderen vs. wissen {#removing-vs-purging}

- **Remove** — stopt terminals en agent, maar de worktree blijft op schijf
- **Purge** — verwijdert worktree en branch permanent (vraagt om bevestiging bij niet-gecommitte wijzigingen)

Wanneer een PR gemerged is, toont Factory Floor een "Purge"-badge zodat je weet dat je veilig kunt opruimen.

### De Coding Agent {#the-coding-agent}

Het Coding Agent-tabblad draait [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) in een ingebouwde terminal. Het zit direct na het Info-tabblad in elke workstream.

#### Agent-instellingen {#agent-settings}

- **Bypass permission prompts** — slaat bevestigingsdialogen over. Handig als je je agent vertrouwt (en graag gevaarlijk leeft).
- **Tmux mode** — verpakt agent-sessies in tmux zodat ze het herstarten van de app overleven. Vereist tmux.
- **Auto-rename branch** — laat de agent de branch hernoemen passend bij de taak.
- **Agent Teams** — experimentele multi-agentcoördinatie, mogelijk gemaakt door Claude Code. We vertrouwen Anthropic, toch?

#### Snelacties {#quick-actions}

Snelacties voeren eenmalige Claude-taken uit vanuit de zijbalk:

- **Commit** — staget en commit met een AI-gegenereerd bericht
- **Push** — pusht de huidige branch naar origin
- **Create PR** — maakt een pull request aan met AI-gegenereerde titel en beschrijving
- **Close PR** — sluit de PR

Deze draaien als achtergrond-`claude -p`-aanroepen. Schakel **Quick action debug mode** in bij de instellingen als je wilt weten hoe de worst gemaakt wordt. Geloof ons, [David](https://davidpoblador.com) heeft meer tijd dan hij wil toegeven besteed aan het debuggen van vreemd gedrag daarbinnen.

---

## Je werkruimte {#your-workspace}

Terminals, browsers en sneltoetsen — het gereedschap in elke workstream.

### Terminals {#terminals}

Terminals worden GPU-gerenderd via [Ghostty](https://ghostty.org). Ze zijn snel.

- **⌘T** — nieuw terminaltab
- **⌘W** — tab sluiten (of Ctrl+D om de shell te beëindigen)
- **⌘1** — Info, **⌘2** — Coding Agent, **⌘3-9** — wisselen tussen tabs
- **⌘Shift+[** / **⌘Shift+]** — door tabs bladeren

Je kunt bestanden en tekst naar de terminal slepen. Want soms is de muis prima, echt waar.

**⌘Shift+E** opent de workstream-map in je favoriete externe terminal-app.

### De browser {#the-browser}

Elke workstream kan browsertabs hebben (⌘B). De browser is ingebouwd — geen vensterwissel nodig.

#### Poortdetectie {#port-detection}

Als je run-script een dev-server start, detecteert Factory Floor de luisterende poort automatisch en navigeert de browser ernaar. Geen configuratie nodig. De `ff-run`-launcher monitort de procesboom op TCP-listeners.

#### Navigatie {#navigation}

- **⌘L** — adresbalk focussen
- **⌘Shift+O** — huidige URL openen in externe browser
- **⌘Click** — opent links in je externe browser

De browser toont een verbindingsfoutpagina met een knop om het opnieuw te proberen als de server nog niet klaar is. Hij navigeert automatisch zodra de poort gedetecteerd wordt.

### Sneltoetsen {#keyboard-shortcuts}

Factory Floor is toetsenbordgericht. Hier is alles.

#### Globaal {#global}

| Sneltoets | Actie |
|----------|--------|
| ⌘N | Nieuwe workstream (of project, als er geen bestaat) |
| ⌘Shift+N | Nieuw project |
| ⌘, | Instellingen |
| ⌘/ | Help |
| ⌘Option+S | Zijbalk in-/uitklappen |

#### Workstream {#workstream}

| Sneltoets | Actie |
|----------|--------|
| ⌘1 | Info |
| ⌘2 | Coding Agent |
| ⌘3-9 | Tabblad wisselen |
| ⌘Shift+[ | Vorig tabblad |
| ⌘Shift+] | Volgend tabblad |
| ⌘Return | Coding Agent focussen |
| ⌘T | Nieuwe terminal |
| ⌘B | Nieuwe browser |
| ⌘W | Tab sluiten |
| ⌘Shift+W | Workstream archiveren |
| ⌘L | Adresbalk (browser) |
| ⌘Shift+Return | Starten/Herstarten |

#### Navigatie {#navigation-1}

| Sneltoets | Actie |
|----------|--------|
| ⌘[ | Vorige workstream |
| ⌘] | Volgende workstream |
| ⌘↑ | Vorig project |
| ⌘↓ | Volgend project |
| ⌘0 | Terug naar project |
| ⌘Option+B | Openen in externe browser |
| ⌘Option+T | Openen in externe terminal |

---

## Configuratie {#configuration}

Zo automatiseer je de saaie stukken.

### Scripts en levenscyclus {#scripts--lifecycle}

Zet een `.factoryfloor.json` in je projectroot om de workstream-levenscyclus te automatiseren.

```json
{
  "setup": "npm install",
  "run": "PORT=$FF_PORT npm run dev",
  "teardown": "docker-compose down"
}
```

| Hook | Wanneer het draait |
|------|-------------|
| `setup` | Eenmalig, bij het aanmaken van een workstream. Dependencies installeren, migraties draaien, wat je maar wilt. |
| `run` | Op aanvraag via het Omgeving-tabblad. Gewrapped in `ff-run` voor poortdetectie. |
| `teardown` | Bij het archiveren of wissen van een workstream. Containers stoppen, opruimen. |

Alle velden zijn optioneel. Scripts draaien in de workstream-map met je login-shell. Ja, zelfs [fish](https://github.com/alltuner/factoryfloor/pull/324). Vraag niet hoe lang dat geduurd heeft.

Factory Floor leest ook `.emdash.json`, `conductor.json` en `.superset/config.json` als `.factoryfloor.json` niet bestaat. Want compatibiliteit is beleefd. (Tijd voor een [standaard](https://xkcd.com/927/)?) Bij fallback-configuratie injecteert Factory Floor compatibele omgevingsvariabelen zodat scripts zonder aanpassingen werken (bijv. `CONDUCTOR_PORT`, `EMDASH_PORT`, `SUPERSET_PORT_BASE`).

#### Het Omgeving-tabblad {#the-environment-tab}

Gesplitste weergave: **Setup** links, **Run** rechts.

- **⌘Shift+Return** — run-script starten/herstarten

### Omgevingsvariabelen {#environment-variables}

Elke terminal, setup-script en run-commando in een workstream heeft deze variabelen:

| Variabele | Wat het is | Voorbeeld |
|----------|-----------|---------|
| `FF_PROJECT` | Projectnaam | `my-app` |
| `FF_WORKSTREAM` | Workstream-naam | `coral-tidal-reef` |
| `FF_PROJECT_DIR` | Pad naar hoofdrepository | `/Users/you/my-app` |
| `FF_WORKTREE_DIR` | Worktree-pad | `~/.factoryfloor/worktrees/my-app/coral-tidal-reef` |
| `FF_PORT` | Deterministische poort (40001-49999) | `42847` |
| `FF_DEFAULT_BRANCH` | Standaard-branch (main, master, etc.) | `main` |

#### Over FF_PORT {#about-ff_port}

Elke workstream krijgt een deterministische poort op basis van een hash van het worktree-pad. Dezelfde workstream, dezelfde poort, elke keer. Geen poortconflicten tussen workstreams. Gebruik het in je run-script: `PORT=$FF_PORT npm run dev`. Als je duizenden workstreams tegelijk draait, krijg je misschien een botsing 🎲, maar hopelijk is je geheugen eerder op.

#### .env-symlink {#env-symlink}

Indien ingeschakeld (Instellingen > Algemeen) maakt Factory Floor symlinks van `.env` en `.env.local` uit je hoofdrepo naar elke worktree. Zo volgen je secrets je zonder kopiëren en plakken. Trouwens, over secrets gesproken, hebben we je al verteld over [Vaultuner](https://vaultuner.alltuner.com)?

### Instellingen {#settings}

Open met **⌘,** of klik op het tandwielpictogram.

#### Algemeen {#general}

- **Basismap** — standaardlocatie voor nieuwe projecten
- **Branch prefix** — prefix voor workstream-branches (standaard: `ff`)
- **Symlink .env files** — automatisch linken van `.env` en `.env.local` in worktrees
- **Theme** — Systeem, Licht of Donker
- **Language** — Systeemstandaard, Engels, Catalaans, Duits, Spaans, Nederlands, Vlaams of Zweeds
- **Confirm before quitting** — vraagt om bevestiging bij afsluiten met actieve workstreams
- **Launch at login** — start Factory Floor bij het inloggen

#### Coding Agent {#coding-agent}

- **Bypass permission prompts** — schakelt bevestigingen voor agent-acties uit
- **Agent Teams** — experimentele multi-agentmodus
- **Auto-rename branch** — agent hernoemt branch bij de eerste prompt
- **Tmux mode** — sessiepersistentie via tmux

#### Apps {#apps}

- **External Terminal** — welke terminal-app geopend wordt met ⌘Shift+E
- **External Browser** — welke browser voor ⌘Shift+O en ⌘Click

#### Geavanceerd {#advanced}

- **Usage analytics** — privacyvriendelijke telemetrie (alleen app-versie, OS, taal)
- **Crash reports** — Sentry-gebaseerde crashrapporten
- **Detailed logging** — logt scriptuitvoer voor debugging
- **Quick action debug mode** — toont ruwe uitvoer van snelacties
- **Bleeding edge updates** — pre-release builds ontvangen
- **Clear project list** — kernoptie, verwijdert alle projecten uit de zijbalk

---

## Integraties {#integrations}

Factory Floor verbinden met al het andere.

### CLI {#cli}

Installeer het `ff`-commando via Instellingen > Omgeving > CLI installeren. Dan:

```
ff /path/to/your/project
```

Opent de map in Factory Floor. Dat is alles wat het doet, en dat is alles wat het hoeft te doen.

### GitHub {#github}

Vereist de [gh CLI](https://cli.github.com/) met authenticatie (`gh auth login`).

- **Projectweergave** — repo-info, beschrijving, sterren, forks, open issues, recente PR's
- **Workstream-zijbalk** — PR-nummer, titel en status (open/merged/closed) per branch
- **Merge-detectie** — toont "Purge"-badge wanneer de PR van een branch gemerged is

#### Snelacties {#quick-actions-1}

Vanuit de zijbalk één-klik-operaties uitvoeren: **Create PR** (AI-gegenereerde titel en beschrijving), **Push** (naar origin met `-u`) of **Close PR** (sluit met commentaar). Want als je het zat bent om voor de honderdste keer "now commit, push, and open a PR" in Claude te typen, ben je niet de enige.

### Updates {#updates}

Factory Floor toont een badge in de zijbalk wanneer er een nieuwere versie beschikbaar is. Je kunt ook handmatig controleren via **Factory Floor > Check for Updates...**

**Homebrew-gebruikers:**

```
brew upgrade factory-floor
```

**DMG-gebruikers:** Updates worden automatisch beheerd via [Sparkle](https://sparkle-project.org). Handmatig controleren via het menu: **Factory Floor > Check for Updates...**

Schakel **Bleeding edge updates** in bij Instellingen > Geavanceerd voor pre-release builds. Voor iedereen die graag op het randje leeft en bugrapporten indient.

---

## Enterprise-functies 😉 {#enterprise-features-}

### Code-editor {#code-editor}

Nee hoor. Geen syntax-highlighting, geen autocomplete, geen minimap. Onze niet-bestaande VC's hebben geen bedrijfsagenda doorgedrukt. We willen dat je de tools gebruikt waar je al van houdt: [Zed](https://zed.dev), [VS Code](https://code.visualstudio.com), wat dan ook. Factory Floor geeft je een Coding Agent, een browser en een worktree. Trouwens, wie schrijft er tegenwoordig nog code?

### Merge-viewer {#merge-viewer}

Ook nee. Je git-client doet dat al beter dan wij ooit zouden kunnen. Wij zorgen er alleen voor dat elke workstream een schone branch heeft die klaar is voor review. Je houdt je PR's toch klein en vermijdt merge-conflicten, toch? ...Toch?

---

## Probleemoplossing {#troubleshooting}

#### "Tools not found" {#tools-not-found}

Factory Floor detecteert tools vanuit je login-shell. Als `claude`, `gh`, `git` of `tmux` niet verschijnen:

- Controleer of ze in je shell-PATH staan
- Fish 4.0- en Nix-gebruikers: de app ondersteunt deze omgevingen, maar als er iets niet klopt, controleer Instellingen > Omgeving

#### Tmux-sessies blijven niet behouden {#tmux-sessions-not-persisting}

- Controleer of tmux geïnstalleerd en gedetecteerd is (Instellingen > Omgeving)
- Factory Floor gebruikt een eigen tmux-socket (`-L factoryfloor`), dus je persoonlijke tmux-configuratie zit niet in de weg

#### Poort niet gedetecteerd {#port-not-detected}

- Zorg dat je run-script `$FF_PORT` gebruikt (of dat de poort uit de procesboom gedetecteerd kan worden)
- De `ff-run`-launcher wrapt het run-script — hij monitort kindprocessen op luisterende TCP-poorten
- Controleer Instellingen > Geavanceerd > Gedetailleerde logging voor debug-uitvoer

#### Iets anders stuk? {#something-else-broken}

- [Bug melden](https://github.com/alltuner/factoryfloor/issues/new?template=bug_report.yml) — vertel ons wat er misging
- [Fix-prompt indienen](https://github.com/alltuner/factoryfloor/issues/new?template=fix_prompt.yml) — schrijf de prompt, wij laten de agent los
- [Iets anders](https://github.com/alltuner/factoryfloor/issues/new) — ideeën, vragen, existentiële twijfels
