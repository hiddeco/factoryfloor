---
title: Privacybeleid
date: 2026-03-16
translationKey: privacy
---

## Samenvatting

Factory Floor verzamelt geen persoonlijke gegevens. Je code blijft op je eigen computer. We verzamelen anonieme crashrapporten om de stabiliteit te verbeteren.

## De applicatie

Factory Floor is een native macOS-applicatie die volledig op je computer draait. De app:

- Stuurt je code, projectinhoud of terminal-uitvoer niet naar een server
- Vereist geen account of registratie
- Volgt je gedrag of activiteiten niet
- Heeft geen toegang tot bestanden buiten je projectmappen

Alle projectgegevens (namen, mappen, workstream-configuraties) worden lokaal op je computer opgeslagen in `~/.config/factoryfloor/`.

## Crashrapporten

Factory Floor gebruikt [Sentry](https://sentry.io/) voor het verzamelen van anonieme crashrapporten. Dit helpt ons stabiliteitsproblemen op te sporen en te verhelpen, met name in de ingebouwde terminal-engine.

**Wat we verzamelen:**

- Crash-stacktraces en foutmeldingen
- App-versie en buildtype (release of development)
- macOS-versie en hardware-architectuur
- Detectie van vastlopers (hoofdthread geblokkeerd >5 seconden)

**Wat we NIET verzamelen:**

- Screenshots of terminal-inhoud
- Bestandspaden, projectnamen of code
- Persoonlijke informatie (namen, e-mailadressen, IP-adressen)
- Toetsaanslagen, klembordinhoud of surfactiviteiten

Crashgegevens worden door Sentry verwerkt binnen de EU (Frankfurt). Je kunt [Sentry's privacybeleid](https://sentry.io/privacy/) bekijken.

## Diensten van derden

Factory Floor integreert met tools die je zelf installeert en configureert:

- **Claude Code** (Anthropic) — bij gebruik van de Coding Agent worden je code en gesprekscontext naar de API van Anthropic gestuurd. Dit is een directe verbinding tussen jouw computer en Anthropic, onderworpen aan [Anthropic's privacybeleid](https://www.anthropic.com/privacy). Factory Floor onderschept, bewaart of routeert deze gegevens niet.
- **GitHub CLI** — onderworpen aan [GitHub's privacyverklaring](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- **Ghostty** — de ingebouwde terminal-engine draait lokaal zonder netwerkactiviteit

Factory Floor treedt niet op als tussenpersoon voor deze diensten. Je API-sleutels en inloggegevens worden direct door elke tool beheerd.

## Deze website

De Factory Floor-website (factory-floor.com) gebruikt [Umami](https://umami.is/) voor privacyvriendelijke analyse. Umami gebruikt geen cookies, verzamelt geen persoonlijke gegevens en voldoet aan de AVG, CCPA en PECR. Alle gegevens zijn geaggregeerd en anoniem.

Er worden geen andere tracking-scripts, advertentienetwerken of analysetools van derden op deze website gebruikt.

## Contact

Neem voor privacygerelateerde vragen contact op met [David Poblador i Garcia](https://davidpoblador.com).
