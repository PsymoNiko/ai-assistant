Zabbix docs ingestion for ai-assistant

What is in this folder:
- zabbix_doc.txt  — full extracted plain text of the upstream PDF (raw source)
- api_index.txt, code_snippets_index.txt — grep-based indexes for quick navigation
- api_jsonrpc_context.txt, jsonrpc_context.txt, python_context_index.txt — targeted context extracts
- zabbix_api_quickstart.md — concise Python + curl examples for common JSON-RPC calls
- memory.json — small extracted "memory" (Q/A + examples) for immediate use by the assistant

How to make this PDF part of the AI knowledge (short):
1) Use the extracted text (zabbix_doc.txt) as canonical source text.
2) Create embeddings for passages (e.g., split into ~500 token passages) with your embedding model.
3) Store embeddings + metadata in the vector store used by the assistant (Milvus/Qdrant/MemDB). See docs/MILVUS_SETUP.md for Milvus.
4) On user query, perform nearest-neighbor search to retrieve context passages and supply them to the LLM as RAG context.

Quick commands (example using Python + sentence-transformers + pymilvus):

# pip install sentence-transformers pymilvus

python - <<'PY'
from sentence_transformers import SentenceTransformer
from pymilvus import Collection, CollectionSchema, FieldSchema, DataType, connections

# Connect and create collection (see docs/MILVUS_SETUP.md)
connections.connect(host='localhost', port=19530)
model = SentenceTransformer('all-MiniLM-L6-v2')
# Split zabbix_doc.txt into passages and embed -> insert into Milvus
PY

If you want, the assistant can:
- Create a small ingestion script that splits zabbix_doc.txt, produces embeddings, and inserts into Milvus/Qdrant.
- Create a direct JSONL of passages ready for your vector DB or for OpenAI embeddings.

Next steps: pick one — (A) create an ingestion script + instructions (Recommended), (B) push embeddings into Milvus now (requires running Milvus), (C) only save the summarized memory.json and quickstart files (done). Choose with the options: [Create script (Recommended), Push to Milvus now, Just save docs].
