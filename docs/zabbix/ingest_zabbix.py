#!/usr/bin/env python3
"""Ingest Zabbix manual into Milvus (or produce JSONL of passages).

Usage examples:

# Install requirements:
# pip install sentence-transformers pymilvus[grpc] tqdm

# Create embeddings with sentence-transformers and push to Milvus:
python docs/zabbix/ingest_zabbix.py \
  --source docs/zabbix/zabbix_doc.txt \
  --milvus-host localhost --milvus-port 19530 \
  --collection zabbix_manual --chunk-size 1000 --overlap 200

# Or just produce JSONL (no Milvus):
python docs/zabbix/ingest_zabbix.py --source docs/zabbix/zabbix_doc.txt --jsonl-only

Supports OpenAI embeddings if you set --use-openai and have OPENAI_API_KEY in env.
"""

import os
import argparse
import json
import math
import uuid
from typing import List, Dict

try:
    from tqdm import tqdm
except Exception:
    def tqdm(x, **_):
        return x


def chunk_text(text: str, chunk_size: int = 1000, overlap: int = 200) -> List[str]:
    paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]
    chunks = []
    current = ""
    for p in paragraphs:
        if not current:
            current = p
            continue
        if len(current) + 1 + len(p) <= chunk_size:
            current = current + "\n\n" + p
        else:
            # flush current in sub-chunks if too long
            while len(current) > chunk_size:
                chunk = current[:chunk_size]
                chunks.append(chunk)
                current = current[chunk_size - overlap:]
            chunks.append(current)
            current = p
    if current:
        # split remaining by chunk_size
        while len(current) > chunk_size:
            chunk = current[:chunk_size]
            chunks.append(chunk)
            current = current[chunk_size - overlap:]
        if current:
            chunks.append(current)
    # final cleanup: strip and dedupe short chunks
    cleaned = [c.strip() for c in chunks if c.strip()]
    return cleaned


def embed_passages_sentence_transformer(passages: List[str], model_name: str = "all-MiniLM-L6-v2") -> List[List[float]]:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer(model_name)
    embeddings = model.encode(passages, show_progress_bar=False, convert_to_numpy=False)
    # SentenceTransformer returns numpy arrays; convert to lists
    return [emb.tolist() if hasattr(emb, 'tolist') else list(emb) for emb in embeddings]


def embed_passages_openai(passages: List[str], model: str = "text-embedding-3-small") -> List[List[float]]:
    import openai
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY not set in environment")
    openai.api_key = key
    embeddings = []
    for i in range(0, len(passages), 16):
        batch = passages[i : i + 16]
        resp = openai.Embedding.create(model=model, input=batch)
        embeddings.extend([item['embedding'] for item in resp['data']])
    return embeddings


def create_milvus_collection(collection_name: str, dim: int = 384):
    from pymilvus import Collection, FieldSchema, CollectionSchema, DataType, connections

    # Assumes connections.connect has already been called
    if Collection.exists(collection_name):
        print(f"Collection '{collection_name}' exists")
        return Collection(collection_name)

    fields = [
        FieldSchema(name="pk", dtype=DataType.INT64, is_primary=True, auto_id=True),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=dim),
        FieldSchema(name="text", dtype=DataType.VARCHAR, max_length=65535),
        FieldSchema(name="source", dtype=DataType.VARCHAR, max_length=256),
        FieldSchema(name="chunk_id", dtype=DataType.VARCHAR, max_length=128)
    ]
    schema = CollectionSchema(fields, description="Zabbix manual passages")
    collection = Collection(name=collection_name, schema=schema)
    index_params = {"index_type": "IVF_FLAT", "metric_type": "COSINE", "params": {"nlist": 1024}}
    collection.create_index(field_name="embedding", index_params=index_params)
    collection.load()
    return collection


def insert_into_milvus(collection, passages: List[str], embeddings: List[List[float]], source: str, batch_size: int = 64):
    from pymilvus import utility
    total = len(passages)
    for i in range(0, total, batch_size):
        batch_passages = passages[i : i + batch_size]
        batch_embs = embeddings[i : i + batch_size]
        chunk_ids = [str(uuid.uuid4()) for _ in batch_passages]
        sources = [source] * len(batch_passages)
        entities = [batch_embs, batch_passages, sources, chunk_ids]
        # alignment: embedding, text, source, chunk_id (must match created schema order)
        collection.insert(entities)
        collection.flush()
        print(f"Inserted {i + len(batch_passages)}/{total}")


def write_jsonl(passages: List[str], outpath: str, metadata: Dict = None):
    with open(outpath, "w", encoding="utf-8") as fh:
        for i, p in enumerate(passages):
            obj = {
                "id": i,
                "text": p,
                "metadata": metadata or {}
            }
            fh.write(json.dumps(obj, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="Path to extracted Zabbix text file")
    parser.add_argument("--collection", default="zabbix_manual", help="Milvus collection name")
    parser.add_argument("--milvus-host", default="localhost")
    parser.add_argument("--milvus-port", default="19530")
    parser.add_argument("--chunk-size", type=int, default=1000)
    parser.add_argument("--overlap", type=int, default=200)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--jsonl-only", action="store_true", help="Do not push to Milvus; only emit JSONL")
    parser.add_argument("--use-openai", action="store_true", help="Use OpenAI embeddings instead of sentence-transformers")
    parser.add_argument("--openai-model", default="text-embedding-3-small", help="OpenAI embedding model")
    parser.add_argument("--st-model", default="all-MiniLM-L6-v2", help="Sentence-transformers model name")
    parser.add_argument("--out-jsonl", default="docs/zabbix/zabbix_passages.jsonl")
    args = parser.parse_args()

    with open(args.source, "r", encoding="utf-8", errors="ignore") as fh:
        text = fh.read()

    passages = chunk_text(text, chunk_size=args.chunk_size, overlap=args.overlap)
    print(f"Produced {len(passages)} passages (chunk_size={args.chunk_size}, overlap={args.overlap})")

    # write JSONL backup
    write_jsonl(passages, args.out_jsonl, metadata={"source_file": args.source})
    print(f"Wrote JSONL -> {args.out_jsonl}")

    if args.jsonl_only:
        print("jsonl-only requested; exiting")
        return

    # get embeddings
    if args.use_openai:
        print("Using OpenAI embeddings")
        embeddings = embed_passages_openai(passages, model=args.openai_model)
        dim = len(embeddings[0])
    else:
        print("Using sentence-transformers embeddings (local)")
        embeddings = embed_passages_sentence_transformer(passages, model_name=args.st_model)
        dim = len(embeddings[0])

    # connect to Milvus
    try:
        from pymilvus import connections
        connections.connect(alias="default", host=args.milvus_host, port=args.milvus_port)
    except Exception as e:
        raise RuntimeError(f"Failed to connect to Milvus: {e}")

    collection = create_milvus_collection(args.collection, dim=dim)
    insert_into_milvus(collection, passages, embeddings, source=os.path.basename(args.source), batch_size=args.batch_size)
    print("Ingestion complete")


if __name__ == "__main__":
    main()
