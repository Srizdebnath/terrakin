<p align="center">
  <img src="art/src/brand/logo-lockup.svg" alt="Terrakin, own the map" width="640">
</p>

# Terrakin

A location-based creature game on **Monad**. Walk the real world to bond with **Kin** at real places. You own each Kin as an NFT. You can claim the **hex** of map you stand in and take a cut of every catch inside it, defend it with on-chain auto-battles, bid on daily **Landmark** zones, fuse and duel Kin in **the Lab**, raid bosses with strangers, trade on a peer-to-peer market and post bounties. Every outcome settles on Monad testnet in about a second.

Android app (Flutter) · Solidity contracts (Foundry) · serverless backend (Vercel) · passkey wallets (Privy).

---

## Download

| | |
|---|---|
| **APK (most phones, 64-bit)** | [`releases/terrakin-1.0.0-arm64.apk`](releases/terrakin-1.0.0-arm64.apk) (28 MB) · also on the [Releases page](../../releases/latest) |
| APK (older 32-bit phones) | [`releases/terrakin-1.0.0-armv7.apk`](releases/terrakin-1.0.0-armv7.apk) (26 MB) |
| Checksums | [`releases/SHA256SUMS.txt`](releases/SHA256SUMS.txt) · signer SHA-256 `62:D7:F3:B3:…:EA:1C:D1:86` |
| Requirements | Android 9+ (API 28), arm64 phone, GPS, a screen lock (needed for passkeys) |
| Network | Monad testnet (chain id `10143`). New players are funded automatically: 0.2 MON and 10 Seed Orbs |

The repo is private, so the links work for collaborators while signed in to GitHub.

**Install:** download the APK on the phone, allow "install unknown apps" for your browser or Files app, open the APK, then sign up with a passkey.

## Important links

| What | Link |
|---|---|
| Backend (config, health) | https://terrakin.vercel.app/api/config · https://terrakin.vercel.app/api/health |
| Passkey domain association | https://terrakin.vercel.app/.well-known/assetlinks.json |
| Block explorer | https://testnet.monadexplorer.com |
| Monad testnet RPC | https://testnet-rpc.monad.xyz |
| Monad faucet (to top up the operator) | https://faucet.monad.xyz |
| Privy dashboard (auth, wallets) | https://dashboard.privy.io |

### Live contracts (Monad testnet)

| Contract | Address | Role |
|---|---|---|
| `Terrakin` | [`0x2C1734aD317A22272053673C67b02E9789b8e895`](https://testnet.monadexplorer.com/address/0x2C1734aD317A22272053673C67b02E9789b8e895) | Kin NFTs, names, orbs, catches, trades, reward pool, module registry |
| `TerrakinCharacters` | [`0xE9361BaF271A19fE13A75AdBE42AAb4875389698`](https://testnet.monadexplorer.com/address/0xE9361BaF271A19fE13A75AdBE42AAb4875389698) | Wayfinder character NFTs |
| `TerrakinTerritory` | [`0x4a448f8c3054824D4311b2EefB92b73657E7Df24`](https://testnet.monadexplorer.com/address/0x4a448f8c3054824D4311b2EefB92b73657E7Df24) | Hexes, defenders, hex battles, Landmark auctions |
| `TerrakinLab` | [`0x860Bb642cE6C279B7915a73e176dd11D09974e04`](https://testnet.monadexplorer.com/address/0x860Bb642cE6C279B7915a73e176dd11D09974e04) | Fusion, re-rolls, orb packs, staked duels (module) |
| `TerrakinCrews` | [`0x70442C6a89493555dD1719529918d1C1B0480Bb2`](https://testnet.monadexplorer.com/address/0x70442C6a89493555dD1719529918d1C1B0480Bb2) | Crews, treasuries |
| `TerrakinSeason` | [`0x6E21b711140e26a13fd44ff40B15291Cf4b3b9b2`](https://testnet.monadexplorer.com/address/0x6E21b711140e26a13fd44ff40B15291Cf4b3b9b2) | Seasons, capped Mythics, player registry, leaderboard |
| `TerrakinMarket` | [`0xb3bB15dCaF65e180d0C9791e769123A8CE8AF513`](https://testnet.monadexplorer.com/address/0xb3bB15dCaF65e180d0C9791e769123A8CE8AF513) | Peer-to-peer Kin market |
| `TerrakinBounties` | [`0x00dce6e923AD74FaF5b8A3f890Ee7e8F0A05F183`](https://testnet.monadexplorer.com/address/0x00dce6e923AD74FaF5b8A3f890Ee7e8F0A05F183) | Location bounties |
| `TerrakinRaids` | [`0x4bf777687D518F0AeAd54F5bc73B6502F04727AD`](https://testnet.monadexplorer.com/address/0x4bf777687D518F0AeAd54F5bc73B6502F04727AD) | Landmark raid bosses (module) |
| Operator / voucher signer | [`0x87435f913da1B8364aB5Ef514Ee1A20736a4f42D`](https://testnet.monadexplorer.com/address/0x87435f913da1B8364aB5Ef514Ee1A20736a4f42D) | Signs vouchers, funds players, owns the contracts |

---

## Contents

1. [What you can do](#what-you-can-do)
2. [System architecture](#1-system-architecture) (diagrams 1–6)
3. [Accounts and onboarding](#2-accounts-and-onboarding) (7–10)
4. [The world and spawns](#3-the-world-and-spawns) (11–14)
5. [Catching Kin](#4-catching-kin) (15–18)
6. [Territory](#5-territory) (19–24)
7. [Battles](#6-battles) (25–27)
8. [The Lab](#7-the-lab) (28–31)
9. [Seasons, leaderboards, crews](#8-seasons-leaderboards-crews) (32–34)
10. [Market, bounties, raids](#9-market-bounties-raids) (35–38)
11. [Economy](#10-economy) (39–41)
12. [Repository layout and building](#repository-layout)
13. [Tests](#tests) · [Design decisions](#design-decisions) · [Known limits](#known-limits)

## What you can do

| Feature | How it works | Settles |
|---|---|---|
| **Catch Kin** | Time the Tether ring, throw an orb (Seed, Bloom, Aurora, Crown), then wobble and reveal | `Terrakin.bond` with a server-signed voucher |
| **Trade** | Two phones within 8 m (Bluetooth + Wi-Fi Direct). Stats shift ±15% at random | `proposeTrade` then `acceptTrade` |
| **Own hexes** | Claim the ~150 m hex you stand in and station 1–3 defenders | `TerrakinTerritory.claim` |
| **Earn rent** | 10% of every catch reward in your hex is paid to you instantly | Inside `bond` |
| **Capture hexes** | Your squad auto-battles the defenders on-chain | `attack` |
| **Landmark auctions** | Bid for tomorrow's Landmark zone. The winner takes 25% of its Landmark catches | `bid` / `settle` |
| **Fusion** | Burn 2 Kin and roll 1: 8% grade up, 70% keep the better grade, 22% dud | `TerrakinLab.fuse` |
| **Re-roll** | Re-roll a Kin's 4 hidden vigor stats (0–15 each) | `reroll` |
| **Orb packs** | 5 random orbs, 2% Crown per orb | `openPack` |
| **Staked duels** | 1–3 Kin vs anyone, anywhere. Winner takes the pot minus 5% | `createDuel` / `acceptDuel` |
| **Seasons** | 30 days, 100 numbered Mythics per species, then sold out | `TerrakinSeason` |
| **Leaderboards** | Turf, Mythics, duel wins, Kin, crews | `leaderboard` view |
| **Crews** | Tag, treasury, equal payouts, crew colours on the map | `TerrakinCrews` |
| **Kin market** | List and buy Kin. Escrow-free, 3% fee | `TerrakinMarket` |
| **Bounties** | "Catch me X within R km by T." The Kin is delivered to the poster | `TerrakinBounties` |
| **Raids** | A daily boss per Landmark with shared HP. Loot is split by damage, plus orbs | `TerrakinRaids` |
| **Share cards** | 1080×1350 meme cards after big moments | Local render |
| **Tone** | Normal or Unhinged (Gen Z and crypto slang) copy | Local |
| **Sound** | Weather-aware music and 16 effects, all synthesised in code | Local |

---

## 1. System architecture

**Diagram 1. The whole system**

```mermaid
flowchart LR
  subgraph Phone["Android phone"]
    App["Flutter app<br/>map, catching, territory, Lab, social"]
    Wallet["Privy embedded wallet<br/>unlocked by passkey"]
    GPS["GPS + compass"]
    BT["Bluetooth / Wi-Fi Direct<br/>(trades)"]
  end
  subgraph Vercel["terrakin.vercel.app"]
    API["Serverless API<br/>config, fund, voucher,<br/>presence, raidpass, enroll, health"]
    AL["/.well-known/assetlinks.json"]
  end
  subgraph Monad["Monad testnet"]
    Core["Terrakin core"]
    Mods["Territory, Lab, Season, Crews,<br/>Market, Bounties, Raids"]
  end
  Privy["Privy auth"]
  Tiles["OpenFreeMap vector tiles"]
  Meteo["Open-Meteo weather"]

  GPS --> App
  BT <--> App
  App <--> Wallet
  Wallet <--> Privy
  App -- "HTTPS + access token" --> API
  API -- "verify token, find wallet" --> Privy
  API -- "operator txs, signatures" --> Core
  API --> Mods
  App -- "eth_call, signed raw txs" --> Core
  App --> Mods
  App --> Tiles
  App --> Meteo
  API --> Meteo
  Privy -. "passkey RP check" .-> AL
```

**Diagram 2. Trust boundaries: what each party can and cannot do**

```mermaid
flowchart TB
  P["Player wallet<br/>signs its own txs, pays its own gas"]
  O["Operator key on Vercel<br/>signs vouchers and passes, funds new players"]
  C["Contracts<br/>verify every signature and rule"]
  P -- "cannot mint a Kin without a voucher" --> C
  O -- "cannot move a player's MON or Kin" --> C
  O -- "can only: fund once per wallet, sign spawn and presence facts, reserve Mythic slots" --> C
  C -- "pays rewards from the pool, enforces ownership" --> P
```

**Diagram 3. Contract map and dependencies**

```mermaid
flowchart LR
  T["Terrakin<br/>(ERC-721 Kin + pool)"]
  CH["TerrakinCharacters<br/>(ERC-721)"]
  TE["TerrakinTerritory"]
  L["TerrakinLab"]
  R["TerrakinRaids"]
  S["TerrakinSeason"]
  CR["TerrakinCrews"]
  M["TerrakinMarket"]
  B["TerrakinBounties"]
  BL[["BattleLib"]]
  OI[["OwnerIndexed"]]
  T --> CH
  T -- "landlord()" --> TE
  TE -- "kinPacked()" --> T
  L -- "module: mint, burn, set, orbs" --> T
  R -- "module: orbs" --> T
  S -- "names, balances" --> T
  S --> TE
  S --> L
  S --> CR
  M -- "transferFrom" --> T
  B -- "kinPacked, transferFrom" --> T
  TE --> BL
  L --> BL
  R --> BL
  T --> OI
  CH --> OI
  CR -- "fees" --> T
```

**Diagram 4. App layers**

```mermaid
flowchart TB
  subgraph UI["screens/"]
    W[world_screen] --- HS[hex_sheet] --- LS[lab_screen] --- SS[season_screen] --- BZ[bazaar_screen] --- RS[raid_sheet] --- BS[battle_screen] --- BD[bond_screen]
  end
  subgraph Svc["chain/ (services)"]
    GC[GameChain] --- TS[TerritoryService] --- LB[LabService] --- SO[SocialService] --- CM[CommerceService] --- AU[AuthService]
  end
  subgraph Core["core/ (pure logic)"]
    HG[hexgrid] --- BT[battle] --- SP[species / kin_stats] --- CP[copy] --- SN[sound] --- EC[economy]
  end
  subgraph Data["data/ + world/"]
    SE[spawn_engine] --- LO[location] --- WE[weather] --- WS[world_store / mvt]
  end
  UI --> Svc --> Core
  UI --> Data
  Svc --> RPC[(Monad RPC)]
  Svc --> API[(Vercel API)]
```

**Diagram 5. Backend endpoints**

```mermaid
flowchart LR
  A["GET /api/config"] --> A1["chain id, RPC, all contract addresses"]
  B["POST /api/fund"] --> B1["Terrakin.fund(player) once, then enrol in season"]
  C["POST /api/voucher"] --> C1["re-derive spawn, check distance and weather,<br/>reserve Mythic serial, sign Bond"]
  D["POST /api/presence"] --> D1["hex id from GPS, sign Presence (120 s)"]
  E["POST /api/raidpass"] --> E1["within 150 m of today's Landmark, sign Pass"]
  F["POST /api/enroll"] --> F1["TerrakinSeason.enrollFor(player)"]
  G["GET /api/health"] --> G1["pool MON, operator MON, players left"]
```

**Diagram 6. Code shared bit for bit between Dart, TypeScript and Solidity**

```mermaid
flowchart LR
  subgraph Dart["app (source of truth)"]
    D1[spawn_engine + rng]
    D2[hexgrid]
    D3[battle]
  end
  subgraph TS["backend"]
    T1[spawn.ts]
    T2[hexgrid.ts]
  end
  subgraph Sol["contracts"]
    S1[BattleLib]
  end
  D1 -- "550 exported vectors" --> T1
  D2 -- "540 exported vectors" --> T2
  S1 -- "10 battle vectors" --> D3
```

---

## 2. Accounts and onboarding

**Diagram 7. First launch, step by step**

```mermaid
sequenceDiagram
  actor U as Player
  participant A as App
  participant P as Privy
  participant V as Vercel
  participant G as Terrakin
  U->>A: Create account with a passkey
  A->>P: passkey.signup(relyingParty=terrakin.vercel.app)
  P-->>A: user + embedded wallet
  A->>V: POST /api/fund (access token)
  V->>P: verify token, look up wallet
  V->>G: fund(wallet) (0.2 MON + 10 Seed Orbs)
  V->>V: enrol in season registry
  U->>A: choose IGN (4–8 chars) + Wayfinder
  A->>G: createProfile(name, style) + 0.02 MON
  A->>U: enable GPS, then the map opens
```

**Diagram 8. Onboarding gate (app state machine)**

```mermaid
stateDiagram-v2
  [*] --> Booting
  Booting --> SignIn: no session
  Booting --> Funding: session
  SignIn --> Funding: passkey ok
  Funding --> Setup: funded, no profile
  Funding --> GPS: has profile
  Setup --> GPS: profile minted
  GPS --> Play: location on
  GPS --> GPS: location off
  Booting --> Error: backend unreachable
  Error --> Booting: retry
```

**Diagram 9. Passkeys on Android**

```mermaid
flowchart LR
  App["xyz.terrakin.terrakin<br/>signed with SHA-256 62:D7:…:86"] -- "Credential Manager" --> GMS["Google Password Manager"]
  GMS -- "fetch" --> AL["terrakin.vercel.app/.well-known/assetlinks.json"]
  AL -- "package + fingerprint match" --> GMS
  GMS -- "attestation" --> Privy
  Privy -- "allowed app id + allowed Android key hash" --> OK["wallet unlocked"]
```

**Diagram 10. A game transaction from the app**

```mermaid
sequenceDiagram
  participant A as App (MonadRpc)
  participant N as Monad RPC
  participant W as Privy wallet
  A->>N: eth_estimateGas, nonce, baseFee, tip (parallel)
  A->>A: gasLimit = estimate + 2% (+30% for random paths) + 2000
  A->>W: eth_signTransaction (type 2, hex fields)
  W-->>A: raw signed tx
  A->>N: eth_sendRawTransaction
  loop every 200 ms
    A->>N: eth_getTransactionReceipt
  end
  N-->>A: receipt + logs (about 1 s, final)
```

---

## 3. The world and spawns

**Diagram 11. Map rendering pipeline**

```mermaid
flowchart LR
  OFM["OpenFreeMap MVT tiles"] --> MVT["mvt.dart decoder"]
  MVT --> WD["world_data: ground, water,<br/>roads, buildings, trees"]
  WD --> WP["WorldPainter<br/>(3D camera, near-plane clipping)"]
  HEX["Territory hexes<br/>(crew colours)"] --> WP
  SKY["SkyPainter<br/>(weather + time of day)"] --> Screen
  WP --> Screen
  BB["Billboards: Kin, Landmarks,<br/>avatar, buddy"] --> Screen
```

**Diagram 12. Spawn kinds**

```mermaid
flowchart TB
  P["Player position + UTC time + weather"] --> W["Wild: 1.5 mdeg cells,<br/>15 min windows"]
  P --> WX["Weather: boosted affinity,<br/>~22% of cells"]
  P --> L["Landmark: 0.04° zones (~4.5 km),<br/>1 per zone per day,<br/>Epic or 20% Mythic"]
  W --> G["Same seed, same Kin<br/>for every player"]
  WX --> G
  L --> G
```

**Diagram 13. How the backend checks a spawn before signing**

```mermaid
flowchart TB
  R["POST /api/voucher<br/>spawnId, species, lat, lng"] --> D{"re-derive spawn<br/>from its id"}
  D -- "unknown" --> X1["404 No such Kin"]
  D --> E{"expired?"}
  E -- "yes" --> X2["410"]
  E --> F{"within 95 m?"}
  F -- "no" --> X3["403 Too far"]
  F --> WT{"weather spawn?"}
  WT -- "yes" --> WC{"sky matches now?"}
  WC -- "no" --> X4["409"]
  WT -- "no" --> SP
  WC --> SP{"species allowed?<br/>(habitat swaps)"}
  SP -- "no" --> X5["409"]
  SP --> MY{"Mythic?"}
  MY -- "yes" --> RES["reserve serial #n/100<br/>or bond as Epic if sold out"]
  MY -- "no" --> SIGN
  RES --> SIGN["sign EIP-712 Bond<br/>(hex + zone included)"]
```

**Diagram 14. Grade odds for wild spawns (%)**

```mermaid
pie showData
  title Wild spawn grades
  "Common" : 62
  "Uncommon" : 26
  "Rare" : 9.5
  "Epic" : 2.3
  "Mythic" : 0.2
```

---

## 4. Catching Kin

**Diagram 15. Encounter state machine**

```mermaid
stateDiagram-v2
  [*] --> Camera: tap a Kin in reach
  Camera --> Tether: photo (Imprint) or skip
  Tether --> Throw: release ring
  Throw --> Wobble
  Wobble --> BrokeFree: miss
  Wobble --> Sealing: caught
  Wobble --> Fled: flee roll
  BrokeFree --> Tether: throw again
  Sealing --> Bonded: voucher + bond tx
  Sealing --> Tether: tx failed, retry
  Bonded --> [*]
  Fled --> [*]
```

**Diagram 16. Catching a Kin on-chain**

```mermaid
sequenceDiagram
  actor U as Player
  participant A as App
  participant V as Vercel
  participant S as Season
  participant G as Terrakin
  participant T as Territory
  U->>A: perfect throw
  A->>V: voucher(spawnId, GPS)
  opt Mythic
    V->>S: reserveMythic(player, species, spawnId)
  end
  V-->>A: Bond voucher + signature (+ serial)
  A->>G: bond(voucher, sig, orbsUsed)
  G->>G: verify signer, burn orbs, mint Kin
  G->>T: landlord(hex, zone, landmark)
  T-->>G: owner or auction winner + cut
  G-->>A: reward (minus cut) paid, owner paid cut
```

**Diagram 17. Orb tiers**

```mermaid
flowchart LR
  S["Seed Orb<br/>x1.0 · 0.0005 MON"] --> B["Bloom Orb<br/>x1.6 · 0.0015"] --> A["Aurora Orb<br/>x2.3 · 0.004"] --> C["Crown Orb<br/>always catches · 0.03"]
```

**Diagram 18. Packed Kin record (one 256-bit storage slot)**

```mermaid
flowchart LR
  a["species 8"] --- b["grade 8"] --- c["trait 8"] --- d["landmark 8"] --- e["trades 16"] --- f["bondedAt 40"] --- g["lat 32"] --- h["lng 32"] --- i["vigor 4×8"] --- j["mods 4×16"]
```

---

## 5. Territory

**Diagram 19. Hex grid construction (pure integer maths, same in Dart and TypeScript)**

```mermaid
flowchart TB
  P["lat, lng in micro-degrees"] --> C["strip = floor(lng / 1°)"]
  C --> X["x = (lng − strip edge) × cosE6(lat) / 1e6"]
  P --> Y["y = lat"]
  X --> AX["axial q, r (pointy-top, size 780 µdeg ≈ 87 m)"]
  Y --> AX
  AX --> RD["cube rounding"]
  RD --> ID["id = (strip+2¹⁵)≪48 | (q+2²³)≪24 | (r+2²³)"]
```

**Diagram 20. Hex lifecycle**

```mermaid
stateDiagram-v2
  [*] --> Unclaimed
  Unclaimed --> Held: claim (stand inside, 0.01 MON, 1–3 defenders)
  Held --> Shielded: changes hands
  Shielded --> Held: 30 min later
  Held --> Held: defence holds (fee to owner)
  Held --> Shielded: attacker wins (new owner)
  Held --> Held: owner restations defenders
```

**Diagram 21. Claiming a hex**

```mermaid
sequenceDiagram
  participant A as App
  participant V as Vercel
  participant T as Territory
  participant G as Terrakin
  A->>V: POST /api/presence (GPS)
  V-->>A: Presence(player, hexId, +120 s), signed
  A->>T: claim(presence, sig, kinIds) + 0.01 MON
  T->>T: verify signer = game.signer()
  T->>G: kinPacked(kinIds) (ownership)
  T->>T: owner = you, shield 30 min, station Kin
  T->>G: claim fee to reward pool
```

**Diagram 22. Who gets the cut of a catch**

```mermaid
flowchart TB
  B["bond() in hex H, zone Z"] --> LM{"Landmark Kin and<br/>auction winner for today?"}
  LM -- "yes" --> W["winner takes 25%"]
  LM -- "no" --> O{"H owned by someone else?"}
  O -- "yes" --> OW["owner takes 10%"]
  O -- "no" --> NONE["catcher keeps 100%"]
```

**Diagram 23. Landmark zone auction timeline**

```mermaid
sequenceDiagram
  participant A as Alice
  participant B as Bob
  participant T as Territory
  Note over T: Day D: bidding for day D+1
  A->>T: bid(zone, D+1) 0.01
  B->>T: bid(zone, D+1) 0.0105 (+5% minimum)
  T->>T: refunds[Alice] += 0.01
  A->>T: withdrawRefund()
  Note over T: Day D+1 begins
  T->>T: settle(zone, D+1): bid to reward pool
  Note over T: All day D+1: Bob takes 25% of Landmark catches in the zone
```

**Diagram 24. Map colours**

```mermaid
flowchart LR
  U["unclaimed"] --> U1["faint outline"]
  M["yours"] --> M1["amber fill and outline"]
  C["crew member's"] --> C1["crew colour (golden-angle hue per crew)"]
  O["anyone else's"] --> O1["colour from owner's address"]
  H["hex you stand in"] --> H1["thicker, brighter outline"]
```

---

## 6. Battles

**Diagram 25. Battle stats from the on-chain record**

```mermaid
flowchart LR
  BASE["species base<br/>hp, atk, def, spd"] --> F
  GR["grade x1.00 / 1.15 / 1.35 / 1.60 / 2.00"] --> F
  VG["vigor 0–15: x(30+v)/30"] --> F
  MD["trade mods 0.70–1.30"] --> F
  F["stat = base × grade × vigor × mod"] --> HP["HP ×2, defenders +10% (home turf)"]
```

**Diagram 26. One turn of the deterministic battle**

```mermaid
flowchart TB
  S["seed = keccak(prevrandao, blockhash, player, …)"] --> R["LCG 64-bit dice"]
  T["turn"] --> SPD{"attacker faster?"}
  SPD -- "yes" --> AH["attacker strikes"]
  SPD -- "no (ties to defender)" --> DH["defender strikes"]
  AH --> DMG["dmg = atk² / (atk+def) × 85–100%, min 1"]
  DH --> DMG
  DMG --> KO{"KO?"}
  KO -- "yes" --> NEXT["next Kin in, turn ends"]
  KO -- "no" --> BACK["other side strikes back"]
  NEXT --> END{"a side out of Kin,<br/>or 48 turns?"}
  BACK --> END
  END -- "turn cap" --> DEF["defence wins"]
```

**Diagram 27. Replays match the chain**

```mermaid
sequenceDiagram
  participant A as App
  participant C as Contract (BattleLib)
  A->>C: attack / acceptDuel / raid attack
  C->>C: simulate(squadA, squadB, seed)
  C-->>A: event with seed, winner, lineups
  A->>A: simulateBattle() in Dart from the same seed
  A->>A: replay every blow (identical to on-chain)
```

---

## 7. The Lab

**Diagram 28. Fusion outcomes**

```mermaid
pie showData
  title Fusion (burn 2, roll 1)
  "Keep the better grade" : 70
  "Dud: the worse grade" : 22
  "Jackpot: one grade up" : 8
```

**Diagram 29. Fusion in detail**

```mermaid
flowchart TB
  A["Kin A"] --> F
  B["Kin B"] --> F["fuse() 0.01 MON"]
  F --> BURN["burn A and B"]
  F --> RNG["block randomness + per-player nonce"]
  RNG --> SPC["species and trait from a random parent"]
  RNG --> VIG["each vigor stat between the parents',<br/>−3…+3 mutation (+2 on jackpot)"]
  RNG --> GRD["grade: jackpot, keep or dud"]
  SPC --> NEW["mint the new Kin (origin of A, mods averaged)"]
  VIG --> NEW
  GRD --> NEW
```

**Diagram 30. Orb pack odds per orb (%)**

```mermaid
pie showData
  title Orb pack (5 orbs, 0.01 MON)
  "Seed" : 70
  "Bloom" : 20
  "Aurora" : 8
  "Crown" : 2
```

**Diagram 31. Staked duel**

```mermaid
sequenceDiagram
  actor C as Creator
  participant L as Lab
  actor X as Challenger
  C->>L: createDuel(squad) + stake
  L-->>X: listed in openDuels()
  X->>L: acceptDuel(id, squad) + equal stake
  L->>L: squads still owned? (else StaleDuel)
  L->>L: coin flip: who attacks
  L->>L: BattleLib.simulate
  L-->>C: pot − 5% to the winner
  L-->>X: (or to the challenger)
  L->>L: duelWins / duelLosses++
```

---

## 8. Seasons, leaderboards, crews

**Diagram 32. Capped Mythics**

```mermaid
flowchart TB
  V["voucher for a Mythic spawn"] --> R{"Season.reserveMythic<br/>(species count < 100?)"}
  R -- "yes" --> N["serial #n/100 on-chain,<br/>Kin bonds as Mythic"]
  R -- "SoldOut or SeasonOver" --> E["Kin bonds as Epic"]
  N --> CNT["public counter: mythicCounts()"]
```

**Diagram 33. Leaderboard data flow**

```mermaid
flowchart LR
  REG["Season player registry<br/>(backend enrols at signup)"] --> LB["leaderboard(offset, 100)<br/>one eth_call per 100 players"]
  T["Terrakin: names, Kin count"] --> LB
  TE["Territory: hexes owned"] --> LB
  L["Lab: duel wins"] --> LB
  S["Season: Mythics this season"] --> LB
  C["Crews: crew id"] --> LB
  LB --> APP["App sorts: Turf, Mythics, Duels, Kin; crews by summed turf"]
```

**Diagram 34. Crew model**

```mermaid
erDiagram
  CREW ||--o{ MEMBER : "up to 30"
  CREW {
    uint id
    string name
    string tag "2-4 chars, unique"
    address captain
    uint treasury
  }
  MEMBER {
    address wallet "one crew per wallet"
  }
  MEMBER ||--o{ HEX : owns
  HEX {
    uint64 id
    colour crew_colour
  }
```

---

## 9. Market, bounties, raids

**Diagram 35. Escrow-free market**

```mermaid
sequenceDiagram
  actor S as Seller
  participant G as Terrakin (ERC-721)
  participant M as Market
  actor B as Buyer
  S->>G: setApprovalForAll(Market) (once)
  S->>M: list(kin, price)
  Note over S: Kin stays with the seller (can still defend hexes)
  B->>M: buy(kin) + price
  M->>M: still owned by the seller? (else Stale)
  M->>G: transferFrom(seller, buyer)
  M-->>S: price − 3%
  M-->>G: 3% to the reward pool
```

**Diagram 36. Bounty matching (checked on-chain)**

```mermaid
flowchart TB
  K["delivered Kin"] --> O{"owned by the hunter?"}
  O --> SP{"species matches<br/>(or 'any')?"}
  SP --> G{"grade ≥ minimum?"}
  G --> T{"bonded after posting,<br/>before the deadline?"}
  T --> D{"origin within radius?<br/>dLat² + (dLng·cos)² ≤ r²"}
  D -- "all yes" --> PAY["Kin to poster, reward − 3% to hunter"]
```

**Diagram 37. Raid boss lifecycle**

```mermaid
stateDiagram-v2
  [*] --> Fresh: new UTC day (8000 HP)
  Fresh --> Damaged: first attack
  Damaged --> Damaged: attacks (0.01 MON each)
  Damaged --> Felled: final blow
  Felled --> Claimable: pot by damage + Aurora Orb each, Crown Orb to finisher
  Damaged --> Expired: day ends
  Expired --> Claimable: pot by damage, no orbs
```

**Diagram 38. A raid attack**

```mermaid
sequenceDiagram
  participant A as App
  participant V as Vercel
  participant R as Raids
  participant G as Terrakin
  A->>V: POST /api/raidpass (GPS)
  V->>V: nearest of 9 zones' Landmarks ≤ 150 m?
  V-->>A: Pass(player, zone, day, +120 s), signed
  A->>R: attack(pass, sig, squad) + 0.01
  R->>G: kinPacked(squad)
  R->>R: squad vs boss at current HP (BattleLib)
  R->>R: damage += …, pot += 95%
  opt boss felled
    R->>G: moduleGiveOrbs(finisher, Crown)
  end
```

---

## 10. Economy

**Diagram 39. Who pays whom in one play session**

```mermaid
flowchart LR
  OP["Operator"] -- "starter grant (via pool) + all backend gas" --> PL["Player"]
  PL -- "orbs, mints, claims, fees" --> POOL(("Reward pool"))
  POOL -- "catch + trade rewards" --> PL
  PL -- "10% of catch rewards in their hex" --> HO["Hex owner"]
  PL -- "25% of Landmark catches" --> AW["Auction winner"]
  PL -- "stake" --> DW["Duel winner (95% of pot)"]
  PL -- "price" --> SE["Seller (97%)"]
  PL -- "bounty reward escrow" --> HU["Hunter (97%)"]
  PL -- "own gas" --> MON["Monad validators"]
```

**Diagram 40. MON in and out of the reward pool (`Terrakin` contract)**

```mermaid
flowchart LR
  subgraph In["Into the pool"]
    i1["character mints"] --- i2["orb buys"] --- i3["hex claims"] --- i4["lost attack fees"] --- i5["auction wins"] --- i6["Lab fees, packs"] --- i7["5% duel house"] --- i8["3% market / bounty fees"] --- i9["5% raid house"] --- i10["crew founding"]
  end
  POOL(("Reward pool"))
  subgraph Out["Out of the pool"]
    o1["starter grants"] --- o2["catch rewards"] --- o3["trade rewards (3/day)"]
  end
  In --> POOL --> Out
```

**Diagram 41. Price sheet (MON, testnet)**

```mermaid
xychart-beta
  title "Catch reward by grade (Landmarks pay x2)"
  x-axis ["Common", "Uncommon", "Rare", "Epic", "Mythic"]
  y-axis "MON" 0 --> 0.9
  bar [0.03, 0.05, 0.1, 0.25, 0.8]
```

| Item | Price | Item | Price |
|---|---|---|---|
| Starter grant | +0.2 | Hex claim | 0.01 |
| First character | 0.02 | Hex attack fee | 0.004 |
| Next character | 0.08 | Auction minimum bid | 0.005 (+5% steps) |
| Seed / Bloom / Aurora / Crown | 0.0005 / 0.0015 / 0.004 / 0.03 | Fusion | 0.01 |
| Trade reward | +0.01 (3 a day) | Re-roll | 0.005 |
| Crew founding | 0.02 | Orb pack | 0.01 |
| Raid entry | 0.01 | Duel stake | from 0.005 |

All prices are adjustable on-chain (`setPrices`) without a redeploy.

---

## Repository layout

```
app/                 Flutter app (Android)
  lib/chain/         Monad RPC, ABI, Privy auth, one service per contract
  lib/core/          hex grid, battle mirror, stats, copy (tone), sound
  lib/data/          spawn engine, GPS, weather, collection
  lib/world/         vector tiles to 3D map painter
  lib/screens/       every screen and sheet
  assets/            Kin art, fonts, synthesised audio
backend/             Vercel serverless API (TypeScript, viem, Privy)
  api/               config, fund, voucher, presence, raidpass, enroll, health
  lib/               spawn + hexgrid ports, chain, season helpers
  public/.well-known assetlinks.json for passkeys
contracts/           Foundry project
  src/               11 contracts and libraries
  test/              5 suites
  script/            Deploy, DeploySocial, DeployCommerce
art/                 SVG masters, logo generator, audio synthesiser
releases/            ready-to-install APKs + checksums
DESIGN.md            visual design system
```

## Building

**App**
```bash
cd app
flutter pub get
flutter test
flutter build apk --release --split-per-abi   # build/app/outputs/flutter-apk/
```
Release builds are signed with the debug key on purpose: its SHA-256 is the one registered in `assetlinks.json` and the Privy dashboard. A new signing key must be added to both, or passkeys stop working.

**Contracts**
```bash
cd contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 foundry-rs/forge-std@v1.17.0 --no-git
forge test
# fresh deployment (resets player state):
OPERATOR_KEY=… POOL=10000000000000000000 forge script script/Deploy.s.sol --rpc-url monad_testnet --broadcast --gas-estimate-multiplier 110
# add modules to a live deployment:
OPERATOR_KEY=… GAME=… TERRITORY=… OLD_LAB=… forge script script/DeploySocial.s.sol   --rpc-url monad_testnet --broadcast
OPERATOR_KEY=… GAME=… forge script script/DeployCommerce.s.sol --rpc-url monad_testnet --broadcast
```

**Backend**
```bash
cd backend
npm install
npm test
vercel --prod
```
Vercel environment variables: `PRIVY_APP_ID`, `PRIVY_APP_SECRET`, `OPERATOR_KEY`, `RPC_URL`, `GAME_ADDRESS`, `CHARACTERS_ADDRESS`, `TERRITORY_ADDRESS`, `LAB_ADDRESS`, `CREWS_ADDRESS`, `SEASON_ADDRESS`, `MARKET_ADDRESS`, `BOUNTIES_ADDRESS`, `RAIDS_ADDRESS`. None of these are in the repo.

**Art and audio**
```bash
python art/tools/logo.py && art/tools/render.sh   # needs fonttools
python art/tools/audio.py                          # needs numpy, scipy, ffmpeg
```

## Tests

| Suite | Count | Covers |
|---|---|---|
| `contracts/test/Terrakin.t.sol` | 12 | names, grant, orbs, vouchers, trades, packing, pool running dry |
| `TerrakinTerritory.t.sol` | 9 | claims, cut, shields, captures, stale defenders, auctions, battle vectors |
| `TerrakinLab.t.sol` | 7 | fusion odds, re-rolls, packs, duels, stale duels, modules |
| `TerrakinSocial.t.sol` | 5 | Mythic caps, seasons, leaderboard, crews end to end |
| `TerrakinCommerce.t.sol` | 6 | market, stale listings, bounty matching, raids, loot |
| `app/test` | 27 | hex grid, battle vectors, ABI, spawns, economy, trade rules |
| `backend/test` | 4 | 550 spawn vectors, 540 hex vectors |
| `backend/scripts/e2e-anvil.ts` | end to end | backend-signed voucher + presence accepted on a local chain |

## Design decisions

- **Monad-friendly state.** Kin ids are hashes, randomness nonces are per player, and there's no global token list (`OwnerIndexed`). Different players' transactions don't touch the same storage, so they run in parallel.
- **Monad bills the gas limit**, not gas used. The app sets the limit to the estimate plus 2% (30% for random-path calls), and the deploy uses a 110% multiplier.
- **Module registry.** New features (Lab, raids, and later ones) are separate contracts that `Terrakin` authorises with `setModule`. Players' Kin and profiles never need a redeploy.
- **No trigonometry on-chain.** Hex and zone ids are computed off-chain with identical integer maths and arrive signed.
- **Escrow-free market.** A listed Kin stays usable (it can defend, duel and raid) until it sells.
- **Sound is ours.** Every note and effect is synthesised by `art/tools/audio.py`. No samples, no licences.

## Known limits

- **Testnet only.** MON has no value here. Staked duels, re-rolls and packs are gambling mechanics. In India, the Promotion and Regulation of Online Gaming Act 2025 restricts real-money online games, so get legal advice before any mainnet launch.
- **GPS can be spoofed.** The backend checks distance against the reported position. Speed and plausibility checks are the next hardening step.
- **The Mythic cap is enforced by the voucher signer** and counted publicly on-chain. The catch function itself doesn't enforce it.
- **Hex grid seams** every 1° of longitude (about 100 km) cut the hexes on that line in half.
- **APKs are published for arm64 and armv7.** x86_64 (emulators) builds from source.
