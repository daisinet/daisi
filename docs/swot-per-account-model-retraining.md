# SWOT Analysis: Per-Account Model Retraining on the Daisi Network

**Concept:** Use the Daisi distributed network to fine-tune small models against each account's own data, producing a custom model tailored to each business. MCP (Model Context Protocol) servers provide the data retrieval layer — connecting accounts' business systems (CRMs, databases, document stores, APIs) to the training pipeline so datasets can be built from live, timely business data.

---

## STRENGTHS (Internal advantages the network already has)

### S1. Per-Account Compute & Storage Isolation
Accounts already own dedicated hosts and have isolated Drive storage with quotas. The architectural boundary for "Account A's model stays on Account A's infrastructure" already exists. This is the hardest part of multi-tenant ML and it's already solved.

### S2. Distributed GPU Infrastructure Already Deployed
Hosts already run GPU inference with auto-tuning for VRAM, layer offloading, and batch sizing (`ModelAutoTuner`). The same hardware that serves inference can potentially serve training jobs — the compute fabric exists and is managed.

### S3. Model Distribution Pipeline Exists
The ORC can push models to hosts via `GetRequiredModels` and broadcast removal with `RemoveModelRequest`. Deploying a retrained model to the right hosts is an extension of existing infrastructure, not a greenfield build.

### S4. GGUF Format Ecosystem
GGUF is the standard for quantized local models. The ecosystem around LoRA/QLoRA fine-tuning that exports back to GGUF is mature (llama.cpp, Unsloth, Axolotl). The host runtime doesn't need to change formats.

### S5. Billing & Usage Tracking Infrastructure
Inference receipts already track tokens, compute time, and account attribution. Extending this to bill for training compute is straightforward.

### S6. Drive as a Training Data Store with Repository-Based Access Control
Drive already supports per-account file storage with erasure coding, quotas, and host-level distribution. Critically, Drive has a **repository-based access model** that maps well to training data partitioning:
- **Account repo**: Shared by all users — ideal for account-wide training data (SOPs, product docs, company knowledge)
- **Private repo**: Creator-only access — user-specific data (personal notes, drafts, individual workflows)
- **Custom repo**: Explicit ACL with `RepositoryAccessEntry` — team/department-level data
- **Managers** (role >= 2) can access everything

This repository model provides the foundation for partitioned RAG and training data, but the vector DB doesn't currently respect it (see W9).

### S7. SecureToolProvider Pattern is a Natural MCP Bridge
The existing SecureToolProvider architecture — remote HTTP endpoints with ORC-validated sessions, per-account credential management, OAuth flows, and bundled plugins — is structurally similar to MCP. Adding MCP server support could follow the same pattern: an MCP server is registered as a SecureToolProvider, the ORC manages credentials, and hosts call MCP endpoints through the existing secure proxy. The 15 existing providers (Google Workspace, Microsoft 365, Firecrawl, etc.) already connect to many of the same data sources MCP would target.

---

## WEAKNESSES (Internal gaps that need to be addressed)

### W1. No Training Data Pipeline — The Biggest Gap
The system stores only inference metadata (token counts, timestamps, model used) — **not conversation content**. There is no passively accumulated training data. Every account starts from zero. Training data must come from:
- **MCP servers** pulling from the account's business systems (CRMs, databases, wikis, ticketing systems)
- Documents/knowledge bases uploaded to Drive
- Explicitly provided Q&A pairs or training datasets
- Opt-in conversation logging (new feature, privacy implications)
- Synthetic data generation from domain documents

MCP is the key to solving this — it turns "the account must manually prepare data" into "the account connects their systems and data flows automatically." Without MCP or a similar connector layer, the burden of producing training data falls entirely on the account.

### W2. No Training Orchestration Layer
Zero RPCs, proto definitions, or services exist for: submitting training jobs, monitoring progress, managing checkpoints, or deploying results. This entire layer must be built from scratch.

### W3. No Per-Account Model Routing
`GetNextHost()` selects hosts by account ownership and availability, but **not** by which model is loaded. There's no mechanism to ensure Account A's inferences hit their retrained model while Account B uses the base model. Model routing per account is a prerequisite.

### W4. No Model Versioning or Rollback
Models are identified by name only — no version tracking, no A/B testing, no safe rollback. If a retrained model performs worse, there's no automated way to revert.

### W5. Training/Inference Resource Contention
Hosts are sized for inference (low latency, small batches, quantized weights). Training requires full-precision weights, larger batches, and sustained GPU utilization. Running both simultaneously will degrade inference or fail on memory-constrained GPUs.

### W6. Small Model Quality Ceiling
Small models (7B-13B) have inherent capability limits. Fine-tuning improves style, domain vocabulary, and task formatting — but cannot teach fundamentally new reasoning. Accounts expecting dramatic capability improvements will be disappointed.

### W7. No Dataset Curation or Preparation Tools
Even if accounts provide raw data, there are no tools for: formatting into training pairs, quality filtering, PII redaction, deduplication, or train/validation splitting. The entire data preparation UX must be built.

### W8. No MCP Client Infrastructure
The network has no MCP implementation. While the SecureToolProvider pattern is architecturally similar, MCP's protocol (JSON-RPC 2.0 over stdio/SSE, resources/tools/prompts/sampling primitives) is distinct and requires a dedicated client implementation. Key gaps:
- No MCP client library in the .NET stack
- No resource discovery or subscription mechanism
- No mapping from MCP resources → training data format
- No UI for accounts to configure MCP server connections
- The existing SecureToolProvider pattern handles execution but not continuous data retrieval/streaming that MCP resources support

### W9. Vector DB Has No User-Level Access Control — Critical for RAG
The vector DB (`VectorDbService`) partitions only by `AccountId`. Every `VectorEntry` stores `FileId`, `ChunkIndex`, `Text`, and `Embedding` — but **no UserId, RepositoryId, or access metadata**. This means:
- A private file uploaded by User A gets vectorized into the account-wide vector store
- User B's RAG search would surface chunks from User A's private files
- There is no way to filter vector search results by repository access permissions

**For safe RAG**, vector entries must carry repository context so searches can be scoped:
- Account repo vectors → visible to all users in the account
- Private repo vectors → visible only to the file creator
- Custom repo vectors → visible only to users in that repo's `AccessList`

The `Search()` method already accepts `filterFileIds`, which could be leveraged — but the caller would need to pre-compute the set of accessible file IDs for the requesting user, which requires joining repository access with file ownership at query time.

---

## OPPORTUNITIES (External factors that favor this direction)

### O1. Massive Market Demand for Private, Custom AI
Enterprises want AI that knows their business but doesn't leak data to third parties. Per-account fine-tuning on private infrastructure is exactly what regulated industries (healthcare, legal, finance) are asking for. This is a premium, high-willingness-to-pay segment.

### O2. LoRA/QLoRA Makes Fine-Tuning Accessible
Modern parameter-efficient fine-tuning (PEFT) needs only 1-4GB of additional VRAM and can produce adapters in hours, not days. A 7B model can be fine-tuned on a single consumer GPU. This aligns with the host hardware profile.

### O3. Competitive Differentiation
OpenAI offers fine-tuning but only on their cloud. Local/private fine-tuning on your own hardware, with your own data, never leaving your network — this is a unique value proposition that no major provider offers as a managed service.

### O4. MCP as the Data Acquisition Layer — Solves the Biggest Weakness
MCP (Model Context Protocol) standardizes how AI systems connect to external data sources. By adding MCP client support, accounts can point the training pipeline at their existing business systems:
- **CRMs** (Salesforce, HubSpot) — customer interaction patterns, product knowledge, sales scripts
- **Knowledge bases** (Confluence, Notion, SharePoint) — SOPs, manuals, internal docs
- **Ticketing systems** (Zendesk, Jira) — support conversations, resolution patterns
- **Databases** — structured business data, product catalogs, transaction history
- **Communication tools** (Slack, Teams archives) — organizational voice and terminology

This transforms the data problem from "accounts must manually curate JSONL files" to "accounts connect their systems and the pipeline extracts training data automatically." MCP's resource/tool/prompt primitives map naturally onto dataset building: resources provide raw data, tools transform it, and prompts guide synthetic data generation.

### O4b. Drive as a Complementary Data Onramp
Accounts already upload documents to Drive. These documents (SOPs, knowledge bases, manuals, FAQs) are exactly the kind of domain knowledge that makes fine-tuning valuable. Drive + MCP together cover both static documents and live business system data.

### O5. Training as a Revenue Stream
Training compute is more expensive than inference. Per-account retraining introduces a new billing dimension: training hours, model artifact storage, and premium support for custom models.

### O6. Open-Source Model Ecosystem is Exploding
New base models ship regularly (Llama, Mistral, Qwen, Gemma, Phi). Each new generation is a better starting point for fine-tuning. Daisi fine-tunes the best available open models rather than training from scratch.

### O7. Adapter Stacking & Composition
LoRA adapters can be hot-swapped and composed. An account could have a "tone" adapter, a "domain knowledge" adapter, and a "task format" adapter — mixing and matching without full retraining. This enables incremental, low-risk customization.

### O8. Opt-In Conversation Logging as a Premium Feature
The absence of stored conversation content is actually a privacy strength. Offering opt-in conversation logging specifically for accounts that want to build training data turns a weakness into a consent-driven feature. Accounts that want custom models explicitly choose to retain their data.

---

## THREATS (External risks and challenges)

### T1. Data Quality Risk — Garbage In, Garbage Out
Most accounts won't have curated, high-quality training data ready to go. Domain documents may be inconsistent, outdated, or poorly structured. Fine-tuning on bad data makes models worse, not better. Without strong curation guardrails, this feature could actively harm model quality.

### T2. High Barrier to Entry for Accounts
Unlike cloud fine-tuning services where you just upload a JSONL file, accounts on Daisi would need to: acquire/prepare training data, understand fine-tuning parameters, evaluate results, and manage model versions — all on distributed infrastructure they may not fully understand. Most SMBs lack the ML expertise to use this effectively.

### T3. Catastrophic Forgetting
Fine-tuning a small model too aggressively on narrow domain data causes it to "forget" general capabilities. An accounting firm's model might get great at tax terminology but lose the ability to write coherent emails. Balancing specialization vs. generality is technically hard.

### T4. Liability & Safety Regression
A retrained model may lose safety guardrails present in the base model. If an account's model generates harmful content because fine-tuning eroded RLHF alignment, who is liable? This introduces legal exposure that doesn't exist with base model inference.

### T5. Support & Expectation Management Burden
Every account's model is unique, meaning every support ticket is unique. "My model gives bad answers" requires investigating that specific account's training data, parameters, and model version. This doesn't scale.

### T6. Compute Economics May Not Work
Training is 10-100x more compute-intensive than inference. If hosts are sized for inference, training jobs will be slow (hours/days on consumer GPUs) or require dedicated hardware. The unit economics need validation.

### T7. Rapid Model Obsolescence
Base models improve every few months. An account that fine-tuned Llama 3 7B will want to migrate to Llama 4 7B. Each migration requires re-training, re-validation, and re-deployment. Custom models accumulate technical debt.

### T8. Competition from Cloud Fine-Tuning
OpenAI, Google, and AWS offer fine-tuning APIs with massive GPU clusters — faster, with better tooling, and increasingly competitive pricing. Daisi's advantage is privacy/locality, but if that's not the primary concern, cloud alternatives win on convenience.

### T9. Data Privacy Complexity
Training data contains the account's business knowledge. If accounts opt into conversation logging for training, GDPR/CCPA deletion requests become complex — does the trained model itself need to be discarded? Machine unlearning is largely unsolved.

---

## Strategic Summary

### The Core Tension
The concept is strategically sound — private, per-account AI models are a genuine market need. But the Daisi network's current architecture is optimized for **inference routing**, not **model training**. The biggest gap isn't compute or infrastructure — it's **training data**. Without stored conversation content, every account must actively build their dataset. **MCP is the key enabler** — it turns passive data sitting in business systems into accessible training material without requiring accounts to manually export and format anything.

### What Exists Today vs. What's Needed

| Capability | Status | Notes |
|---|---|---|
| Per-account compute isolation | Ready | Accounts own hosts |
| Per-account storage | Ready | Drive with quotas |
| Model distribution to hosts | Ready | ORC push mechanism |
| SecureToolProvider pattern | Ready | Foundation for MCP bridge |
| MCP client support | **Not built** | No MCP protocol implementation |
| Training data from business systems | **Not built** | Needs MCP + data pipeline |
| Training data from inference logs | **Not available** | Only metadata stored |
| Training data from Drive docs | Partially ready | Storage exists, pipeline doesn't |
| Training orchestration | **Not built** | No RPCs, no scheduler |
| Per-account model routing | **Not built** | GetNextHost doesn't filter by model |
| Model versioning/rollback | **Not built** | Name-only identification |
| Dataset preparation tools | **Not built** | No curation, formatting, or QA |

### Recommended Approach: MCP-First, Then Train

**Phase 1 — Access-Controlled RAG + MCP Data Connectors**
Two parallel workstreams:
- **RAG access control**: Extend vector DB entries with `RepositoryId` and `CreatedByUserId` metadata. At search time, resolve the requesting user's accessible repositories (Account repo + their Private repo + Custom repos they're in), then filter vector results to only return chunks from files in those repos. This ensures private files stay private even through semantic search.
- **MCP client**: Build MCP client support into the host/ORC layer. Let accounts connect their business systems (CRMs, knowledge bases, databases, ticketing). Ingest MCP-retrieved data into Drive (respecting repository partitioning) and the vector DB for immediate RAG use — no retraining needed.

**Phase 2 — Automated Dataset Building**
Use MCP-retrieved data + Drive documents to automatically generate training datasets. The pipeline: MCP pulls raw data → preprocessing extracts Q&A pairs, domain terminology, business patterns → formatting produces JSONL training sets → storage in Drive. Training datasets built from account-wide repos produce account-level model improvements; user-private data is excluded from shared training sets unless explicitly opted in. Optionally add opt-in conversation logging for accounts that want to include interaction data.

**Phase 3 — LoRA Adapter Fine-Tuning**
Once an account has sufficient data (from MCP sources + Drive docs + opted-in conversations), offer LoRA fine-tuning as a premium feature. Start with domain knowledge and terminology, then expand to style/tone adaptation.

**Phase 4 — Full Training Orchestration**
Build the complete training pipeline (job scheduling, monitoring, versioning, safety evaluation) once Phase 3 validates demand and economics.

This phased approach solves the data problem first (via MCP), delivers value immediately (via RAG), and builds toward full custom models incrementally.
