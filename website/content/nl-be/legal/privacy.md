---
title: Privacybeleid
date: 2026-03-16
translationKey: privacy
---

## Kort samengevat

Factory Floor verzamelt geen persoonlijke gegevens. Je code blijft op je computer. We verzamelen anonieme crashrapporten om de stabiliteit te verbeteren.

## De applicatie

Factory Floor is een native macOS-applicatie die volledig op je computer draait. Ze:

- Stuurt je code, projectinhoud of terminal-uitvoer niet naar een server
- Vereist geen account of registratie
- Volgt je gedrag of activiteiten niet
- Heeft geen toegang tot bestanden buiten je projectmappen

Alle projectgegevens (namen, mappen, workstream-configuraties) worden lokaal op je computer opgeslagen in `~/.config/factoryfloor/`.

## Crashrapporten

Factory Floor gebruikt [Sentry](https://sentry.io/) om anonieme crashrapporten te verzamelen. Dit helpt ons om stabiliteitsproblemen te identificeren en op te lossen, vooral in de ingebouwde terminal-engine.

**Wat er verzameld wordt:**

- Crash-stacktraces en foutmeldingen
- Appversie en buildtype (release of ontwikkeling)
- macOS-versie en hardware-architectuur
- Detectie van vastlopers (hoofdthread geblokkeerd >5 seconden)

**Wat er NIET verzameld wordt:**

- Screenshots of terminal-inhoud
- Bestandspaden, projectnamen of code
- Persoonlijke informatie (namen, e-mailadressen, IP-adressen)
- Toetsaanslagen, klembordinhoud of surfgedrag

Crashgegevens worden door Sentry verwerkt binnen de EU (Frankfurt). Je kunt [Sentry's privacybeleid](https://sentry.io/privacy/) raadplegen.

## Diensten van derden

Factory Floor integreert met tools die je zelf installeert en configureert:

- **Claude Code** (Anthropic) — bij gebruik van de Coding Agent worden je code en gesprekscontext naar de API van Anthropic gestuurd. Dit is een rechtstreekse verbinding tussen je computer en Anthropic, onderworpen aan [Anthropic's privacybeleid](https://www.anthropic.com/privacy). Factory Floor onderschept, bewaart of routeert deze gegevens niet.
- **GitHub CLI** — onderworpen aan [GitHub's privacybeleid](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- **Ghostty** — de ingebouwde terminal-engine draait lokaal zonder netwerkactiviteit

Factory Floor treedt niet op als tussenpersoon voor deze diensten. Je API-sleutels en inloggegevens worden rechtstreeks door elke tool beheerd.

## Deze website

De Factory Floor-website (factory-floor.com) gebruikt [Umami](https://umami.is/) voor privacyvriendelijke analyse. Umami gebruikt geen cookies, verzamelt geen persoonlijke gegevens en voldoet aan GDPR, CCPA en PECR. Alle gegevens zijn geaggregeerd en anoniem.

Er worden geen andere tracking-scripts, advertentienetwerken of analyses van derden gebruikt op deze website.

## Contact

Voor vragen over privacy, neem contact op met [David Poblador i Garcia](https://davidpoblador.com).
