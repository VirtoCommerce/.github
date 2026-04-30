![The Only B2B eCommerce Platform - You'll Ever Need](https://github.com/user-attachments/assets/01be73ce-e578-4843-91cc-61543f7929c9)

[![Home](https://img.shields.io/badge/Website-virtocommerce.com-FF6B35?style=flat-square&logo=googlechrome&logoColor=white)](https://virtocommerce.com/)
[![Interactive Demo](https://img.shields.io/badge/Live%20Demo-Try%20it%20now-22C55E?style=flat-square&logo=rocket&logoColor=white)](https://virtocommerce.com/interactive-demo)
[![Documentation](https://img.shields.io/badge/Docs-docs.virtocommerce.org-0078D4?style=flat-square&logo=readthedocs&logoColor=white)](https://docs.virtocommerce.org/)
[![Community](https://img.shields.io/badge/Community-virtocommerce.org-7B68EE?style=flat-square&logo=discourse&logoColor=white)](https://www.virtocommerce.org/)

**Virto Commerce** is an open-source, .NET-based, headless, API-first commerce platform — built B2B-first, ready for B2C, marketplace, DTC, and composable scenarios. This page is the entry point for developers: spin it up, understand what you're building, and ship.

## JOIN US NOW
👉 [Explore Virto Commerce](https://virtocommerce.com/)

👉 [Virto Commerce B2B Marketplace](https://virtocommerce.com/solutions/marketplace)

👉 [Explore Virto’s Open-Source .NET ecommerce platform](https://virtocommerce.com/open-source-net-ecommerce-platform)

👉 [Learn more about B2B features of Virto’s platform](https://virtocommerce.com/b2b-ecommerce-platform)

👉 [Browse careers at Virto Commerce](https://virtocommerce.com/career)

## WHO WE ARE
As a Microsoft Gold Partner, Virto serves over 100 companies worldwide and has offices in five countries, including the Americas and Europe. Leveraging our open-source ecommerce platform, hosted solution and full-service offering, our clients strategically use ecommerce to build stronger customer relationships and rapidly increase global online sales. Virto Commerce’s flagship product, the ecommerce cloud-based, open-source, [.NET platform](https://virtocommerce.com/open-source-net-ecommerce-platform), is the only [B2B-first headless digital commerce solution](https://virtocommerce.com/b2b-headless-ecommerce-solution) that is specifically designed to adapt to ever-changing complex scenarios common in the B2B market. 

## WHAT AND HOW WE DO IT
At Virto Commerce, we pride ourselves on being proactive technology innovators deeply dedicated to creating flexible, agile commerce software solutions that improve business and accelerate digital adoption. All this requires a special mindset and a lot of collaborative effort to make complex things simple. We believe in the uniting power of technology, teamwork and spirit, and we take personal responsibility for every project we undertake.

## 🚀 How to Start

### Step 0. Hello World

👨‍💻 [Download and Read - Virto Architectural Guidelines](https://virtocommerce.com/atomic-architecture)

👨‍💻 [Ask Virto Oz – Your Conversational AI Copilot](https://virtocommerce.com/)

### Step 1. Run a demo in minutes

Use **[start-local](https://github.com/VirtoCommerce/start-local)** to bring up the full stack (platform, frontend, database, Redis, Elasticsearch, Kibana) on your machine with one PowerShell command.

```powershell
$installSCript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/VirtoCommerce/start-local/dev/VirtoLocal_create_local_files.ps1" -UseBasicParsing; Set-Content -Path ".\VirtoLocal_create_local_files.ps1" -Value $installSCript.Content; .\VirtoLocal_create_local_files.ps1
```

### Step 2. Build a Proof of Concept (PoC) — extend, don't fork

👨‍💻 [What are the skills required for Virto Commerce Developer?](https://www.virtocommerce.org/t/what-are-the-skills-required-for-virto-commerce-developer/90)

👨‍💻 [Virto Commerce Dev Training Program](https://www.virtocommerce.org/t/virto-commerce-dev-training-program/786/1)

👨‍💻 [Virto Commerce Documentation](https://docs.virtocommerce.org/) 

Virto Commerce is designed to be extended [through custom modules](https://docs.virtocommerce.org/platform/developer-guide/latest/Tutorials-and-How-tos/Tutorials/creating-custom-module/), not by modifying the platform source. The Extensibility Framework lets you add entities, override services, extend APIs, and add admin UI — all without forking.

```powershell
dotnet new install VirtoCommerce.Module.Template
dotnet new vc-module --ModuleName MyModule --Author "Me" --CompanyName MyCompany
```

Build with **[vc-build](https://github.com/VirtoCommerce/vc-build)**, install the resulting `.zip` into your local platform via **Modules → Advanced → Install from file**, and iterate.

```powershell
vc-build compress
```

### Step 3. Build your own solution — production-ready

A Virto solution is **composed**, not forked:

| Layer | What you do | Repo strategy |
|---|---|---|
| **Platform** | Use Virto's official Docker images or binary package | ❌ No fork |
| **Custom modules** | One repo per module, generated from the template | ✅ Your repos |
| **Frontend** | Brand and extend the storefront | ✅ Fork [vc-frontend](https://github.com/VirtoCommerce/vc-frontend), track upstream |
| **Deployment** | Compose the environment from independent images | ✅ Virto Cloud, Azure, AWS, on-prem |

This separation enables seamless Virto upgrades — your customisations stay yours, and the platform stays current.

📖 [Deploy on Virto Cloud](https://docs.virtocommerce.org/platform/deployment-on-cloud/3.0/deploy-on-virto-cloud/)

## Releases

### Virto Commerce Release Strategy
Virto Commerce ships as **modules** — independently versioned, independently deployable units. Modules combine into bundles you can pick from based on how you want to balance stability and speed.

| Release Strategy | What it is | Use it for |
|---|---|---|
| **Stable** | Quarterly release; passed full regression, E2E, and load testing | Production, new solution development (default in vc-build) |
| **Hotfix** | Bug fixes for the two most recent stable releases | Maintenance updates between stable cuts |
| **Edge** | Latest features as they land — minimal risk, maximum freshness | Early access to new capabilities, prototyping |


### Release Notes
> [!TIP]
> Open any deck via the links above, or clone the repo and open the `index.html` files directly in your browser. Add a feature to your backlog, then navigate to the Backlog screen and click **Copy as Markdown**. 

| Month | Live deck | Source notes |
| --- | --- | --- |
| **April 2026** | [📊 View deck](https://virtocommerce.github.io/vc-release-notes/2026-04/) | [Notes](https://www.virtocommerce.org/t/virto-s-release-notes-april-2026/847) |
| **March 2026** | [📊 View deck](https://virtocommerce.github.io/vc-release-notes/2026-03/) | [Notes](https://www.virtocommerce.org/t/virto-s-release-notes-march-2026/839) |
| **February 2026** | [📊 View deck](https://virtocommerce.github.io/vc-release-notes/2026-02/) | [Notes](https://www.virtocommerce.org/t/virto-s-release-notes-february-2026/834) |
| **January 2026** | [📊 View deck](https://virtocommerce.github.io/vc-release-notes/2026-01/) | [Notes](https://www.virtocommerce.org/t/virto-s-release-notes-january-2026/821) |

[Previuos Releases](https://www.virtocommerce.org/c/news-digest/15) 

## 🤝 Contributing

We welcome contributions — code, docs, bug reports, feature ideas. The fastest path:

1. **Fork** the relevant repo (e.g., [vc-platform](https://github.com/VirtoCommerce/vc-platform), [vc-module-catalog](https://github.com/VirtoCommerce/vc-module-catalog), [vc-frontend](https://github.com/VirtoCommerce/vc-frontend)).
2. **Branch from `dev`** — not `master`. Create a topic branch: `git checkout -b feature/short-description`.
3. **Commit and push** to your fork, then open a pull request against the upstream `dev` branch.
4. **Sign the CLA** when prompted on your first PR — required for all contributors.
5. Each PR automatically produces an **Alpha release** so you can test your changes against a real build before merge.

### Where to start

- 🐛 Browse [open issues](https://github.com/search?q=org%3AVirtoCommerce+is%3Aissue+is%3Aopen&type=issues) — issues labelled **good first issue** are best for newcomers.
- 💡 For larger ideas, [open a discussion](https://www.virtocommerce.org/) or an issue *before* coding so maintainers can shape the approach.
- 📝 Documentation fixes (typos, broken links, clarifications) are always welcome and the easiest way to get familiar with the workflow.

📖 [Full contribution guide with step-by-step Git walkthrough](https://www.virtocommerce.org/t/how-to-contribute-to-virto-commerce/459)
