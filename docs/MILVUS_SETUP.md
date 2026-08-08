# Milvus Vector Database for ai-assistant RAG

Complete guide for using Milvus as an alternative vector database for Retrieval-Augmented Generation (RAG).

---

## Overview: Milvus vs Qdrant

| Feature | Milvus | Qdrant |
|---------|--------|--------|
| Type | Vector DB + Search Engine | Vector DB |
| Deployment | Standalone, Docker, K8s | Standalone, Docker, K8s |
| Scalability | Distributed architecture | Single-node optimized |
| GPU Support | ✅ (GPU-accelerated FAISS) | ❌ CPU only |
| Memory Efficiency | Better for large datasets | Better for small/medium |
| API | gRPC, RESTful | RESTful |
| Python Client | Official SDK | Official SDK |
| Best For | Large-scale, enterprise | Simplicity, fast setup |

---

## Part 1: Milvus Installation

### Option A: Docker Compose (Recommended)

Add to `docker-compose.yml`:

```yaml
services:
  milvus:
    image: milvusdb/milvus:latest
    container_name: milvus
    restart: always
    ports:
      - "19530:19530"     # gRPC port
      - "9091:9091"       # HTTP port
    environment:
      COMMON_STORAGETYPE: local
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
    volumes:
      - milvus_data:/var/lib/milvus
    depends_on:
      - etcd
      - minio
    networks:
      - default

  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    container_name: milvus_etcd
    restart: always
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
      - ETCD_SNAPSHOT_COUNT=50000
    volumes:
      - etcd_data:/etcd
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls http://0.0.0.0:2379 --data-dir /etcd

  minio:
    image: minio/minio:latest
    container_name: milvus_minio
    restart: always
    environment:
      MINIO_STORAGE_USE_HTTPS: "false"
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - minio_data:/minio_data
    command: minio server /minio_data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"

volumes:
  milvus_data:
  etcd_data:
  minio_data:
```

Start services:

```bash
docker-compose up -d milvus etcd minio

# Wait for startup (30-60 seconds)
sleep 30

# Test connection
python3 << 'EOF'
from pymilvus import connections
connections.connect(alias="default", host="localhost", port=19530)
print("✅ Milvus connected!")
EOF
```

### Option B: Helm on Kubernetes

```bash
# Add Milvus helm repo
helm repo add milvus https://milvusdb.com/milvus-helm
helm repo update

# Install
helm install milvus milvus/milvus --namespace milvus --create-namespace

# Port forward
kubectl port-forward -n milvus svc/milvus 19530:19530
```

---

## Part 2: Python Client Setup

### Install Milvus SDK

```bash
pip install pymilvus
```

### Connection Test

Create `test_milvus.py`:

```python
from pymilvus import connections, Collection, FieldSchema, CollectionSchema, DataType

# Connect to Milvus
connections.connect(
    alias="default",
    host="localhost",
    port=19530
)

print("✅ Connected to Milvus")

# Check server info
from pymilvus import utility
print(f"Server version: {utility.get_server_version()}")
print(f"Collections: {utility.list_collections()}")
```

Run:

```bash
python test_milvus.py
```

---

## Part 3: Vector Database Operations

### Create Milvus Client

Create `src/backend/rag/milvus_client.py`:

```python
"""Milvus vector database client for RAG"""

from pymilvus import (
    connections, Collection, FieldSchema, CollectionSchema, DataType, Field
)
from typing import List, Dict, Tuple
import uuid

class MilvusDB:
    def __init__(self, collection_name: str = "ai-assistant-docs", 
                 host: str = "localhost", port: int = 19530):
        """Initialize Milvus client"""
        
        self.collection_name = collection_name
        self.host = host
        self.port = port
        
        # Connect
        connections.connect(
            alias="default",
            host=host,
            port=port
        )
        
        self.dimension = 384  # MiniLM-L6-v2
        self._create_collection_if_not_exists()
    
    def _create_collection_if_not_exists(self):
        """Create collection with proper schema"""
        
        from pymilvus import utility
        
        if utility.has_collection(self.collection_name):
            print(f"Collection '{self.collection_name}' exists")
            return
        
        # Define schema
        fields = [
            FieldSchema(
                name="id",
                dtype=DataType.INT64,
                is_primary=True,
                auto_id=True
            ),
            FieldSchema(
                name="embedding",
                dtype=DataType.FLOAT_VECTOR,
                dim=self.dimension
            ),
            FieldSchema(
                name="text",
                dtype=DataType.VARCHAR,
                max_length=65535
            ),
            FieldSchema(
                name="source",
                dtype=DataType.VARCHAR,
                max_length=256
            ),
            FieldSchema(
                name="category",
                dtype=DataType.VARCHAR,
                max_length=256
            ),
            FieldSchema(
                name="doc_id",
                dtype=DataType.VARCHAR,
                max_length=256
            )
        ]
        
        schema = CollectionSchema(
            fields=fields,
            description=f"Vector store for {self.collection_name}"
        )
        
        # Create collection
        collection = Collection(
            name=self.collection_name,
            schema=schema
        )
        
        # Create index on embeddings
        index_params = {
            "index_type": "IVF_FLAT",
            "metric_type": "COSINE",
            "params": {
                "nlist": 1024
            }
        }
        
        collection.create_index(
            field_name="embedding",
            index_params=index_params
        )
        
        print(f"✅ Created collection '{self.collection_name}'")
    
    def add_document(self, text: str, metadata: Dict) -> str:
        """Add single document"""
        
        from src.backend.rag.embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        embedding = model.embed_text(text)
        
        doc_id = str(uuid.uuid4())
        
        collection = Collection(self.collection_name)
        
        entities = [
            [embedding],  # embeddings
            [text],       # text
            [metadata.get("source", "unknown")],
            [metadata.get("category", "general")],
            [doc_id]
        ]
        
        collection.insert(entities)
        collection.flush()
        
        return doc_id
    
    def add_documents(self, documents: List[Dict]) -> List[str]:
        """Add multiple documents efficiently
        
        Args:
            documents: List with 'text' and 'metadata' keys
        """
        
        from src.backend.rag.embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        texts = [doc["text"] for doc in documents]
        embeddings = model.embed_texts(texts)
        
        collection = Collection(self.collection_name)
        
        # Prepare entities
        embedding_list = []
        text_list = []
        source_list = []
        category_list = []
        doc_id_list = []
        
        for embedding, doc in zip(embeddings, documents):
            doc_id = str(uuid.uuid4())
            
            embedding_list.append(embedding)
            text_list.append(doc["text"])
            source_list.append(doc.get("metadata", {}).get("source", "unknown"))
            category_list.append(doc.get("metadata", {}).get("category", "general"))
            doc_id_list.append(doc_id)
        
        entities = [
            embedding_list,
            text_list,
            source_list,
            category_list,
            doc_id_list
        ]
        
        # Insert
        collection.insert(entities)
        collection.flush()
        
        print(f"✅ Inserted {len(documents)} documents")
        
        return doc_id_list
    
    def search(self, query: str, limit: int = 5) -> List[Tuple[str, float]]:
        """Search for similar documents
        
        Returns:
            List of (text, similarity_score) tuples
        """
        
        from src.backend.rag.embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        query_embedding = model.embed_text(query)
        
        collection = Collection(self.collection_name)
        collection.load()  # Load collection into memory
        
        # Search
        search_params = {
            "metric_type": "COSINE",
            "params": {"nprobe": 10}
        }
        
        results = collection.search(
            data=[query_embedding],
            anns_field="embedding",
            param=search_params,
            limit=limit,
            output_fields=["text", "source", "category", "doc_id"]
        )
        
        # Format results
        output = []
        for result in results[0]:
            output.append((
                result.entity.get("text"),
                result.distance
            ))
        
        return output
    
    def search_with_metadata(self, query: str, limit: int = 5) -> List[Dict]:
        """Search and return full metadata"""
        
        from src.backend.rag.embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        query_embedding = model.embed_text(query)
        
        collection = Collection(self.collection_name)
        collection.load()
        
        search_params = {
            "metric_type": "COSINE",
            "params": {"nprobe": 10}
        }
        
        results = collection.search(
            data=[query_embedding],
            anns_field="embedding",
            param=search_params,
            limit=limit,
            output_fields=["text", "source", "category", "doc_id"]
        )
        
        # Format results
        output = []
        for result in results[0]:
            output.append({
                "text": result.entity.get("text"),
                "score": result.distance,
                "source": result.entity.get("source"),
                "category": result.entity.get("category"),
                "doc_id": result.entity.get("doc_id")
            })
        
        return output
    
    def delete_by_doc_id(self, doc_id: str):
        """Delete document by ID"""
        
        collection = Collection(self.collection_name)
        collection.delete(expr=f'doc_id == "{doc_id}"')
        collection.flush()
    
    def get_stats(self) -> Dict:
        """Get collection statistics"""
        
        collection = Collection(self.collection_name)
        
        return {
            "collection": self.collection_name,
            "num_entities": collection.num_entities,
            "dimension": self.dimension
        }

# Example usage
if __name__ == "__main__":
    db = MilvusDB()
    
    # Add sample documents
    docs = [
        {
            "text": "To deploy the gateway, run: docker-compose up -d gateway",
            "metadata": {"source": "deployment.md", "category": "deployment"}
        },
        {
            "text": "Monitor system with: docker stats",
            "metadata": {"source": "monitoring.md", "category": "monitoring"}
        }
    ]
    
    db.add_documents(docs)
    
    # Search
    results = db.search_with_metadata("How to deploy?", limit=3)
    
    print(f"\nSearch results:")
    for r in results:
        print(f"  Score: {r['score']:.2f} | {r['text'][:50]}...")
    
    # Stats
    print(f"\nCollection stats: {db.get_stats()}")
```

---

## Part 4: Integration with RAG

### Update Gateway

Add to `src/backend/gateway/app/main.py`:

```python
from src.backend.rag.milvus_client import MilvusDB

milvus_db = MilvusDB(
    collection_name="ai-assistant-docs",
    host=os.getenv("MILVUS_HOST", "localhost"),
    port=int(os.getenv("MILVUS_PORT", 19530))
)

@app.post("/rag/search/milvus")
async def rag_search_milvus(query: str, limit: int = 5):
    """Search Milvus for relevant documents"""
    try:
        results = milvus_db.search_with_metadata(query, limit=limit)
        return {"results": results}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

@app.post("/rag/augment/milvus")
async def rag_augment_milvus(message: str, limit: int = 5):
    """Augment with Milvus context"""
    try:
        docs = milvus_db.search(message, limit=limit)
        context = "\n\n".join([f"[{score:.2f}] {text}" for text, score in docs])
        
        return {
            "original_query": message,
            "context_documents": len(docs),
            "augmented_prompt": f"Context:\n{context}\n\nQuestion: {message}"
        }
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
```

### Update docker-compose.yml

```yaml
environment:
  MILVUS_HOST=milvus
  MILVUS_PORT=19530
```

---

## Part 5: Performance Tuning

### Index Types

```python
# IVF (Inverted File) - Good balance
index_params = {
    "index_type": "IVF_FLAT",
    "metric_type": "COSINE",
    "params": {"nlist": 1024}
}

# HNSW - Better accuracy
index_params = {
    "index_type": "HNSW",
    "metric_type": "COSINE",
    "params": {"M": 4, "efConstruction": 200}
}

# GPU-accelerated (if GPU available)
index_params = {
    "index_type": "GPU_BRUTE_FORCE",
    "metric_type": "COSINE"
}
```

### Memory Management

```python
# Load collection into memory for faster search
collection = Collection("ai-assistant-docs")
collection.load()

# Release from memory when done
collection.release()

# Partition pruning for large datasets
collection.create_partition("partition_1")
```

---

## Part 6: Comparison: Milvus vs Qdrant

### When to use Milvus:

✅ Large-scale datasets (millions of documents)
✅ GPU acceleration needed
✅ Enterprise deployment
✅ High throughput requirements
✅ Horizontal scaling needed

### When to use Qdrant:

✅ Small to medium datasets
✅ Simple single-node setup
✅ Fastest time to value
✅ Lower resource usage
✅ REST API preferred

---

## Part 7: Migration from Qdrant to Milvus

```python
"""Migrate documents from Qdrant to Milvus"""

from src.backend.rag.qdrant_client import QdrantDB as QdrantDBOld
from src.backend.rag.milvus_client import MilvusDB

# Read from Qdrant
qdrant = QdrantDBOld()
scroll_results = qdrant.client.scroll(
    collection_name="ai-assistant-docs",
    limit=100,
    with_payload=True,
    with_vectors=True
)

# Write to Milvus
milvus = MilvusDB()

for point in scroll_results[0]:
    doc = {
        "text": point.payload["text"],
        "metadata": {
            "source": point.payload.get("source"),
            "category": point.payload.get("category")
        }
    }
    milvus.add_document(doc["text"], doc["metadata"])

print("✅ Migration complete!")
```

---

## Part 8: Environment Variables

Add to `.env`:

```bash
# Milvus Configuration
MILVUS_HOST=localhost
MILVUS_PORT=19530
MILVUS_COLLECTION=ai-assistant-docs
MILVUS_INDEX_TYPE=IVF_FLAT
MILVUS_METRIC_TYPE=COSINE
MILVUS_NLIST=1024

# ETCD (for distributed Milvus)
ETCD_ENDPOINTS=etcd:2379

# MinIO (object storage for Milvus)
MINIO_ADDRESS=minio:9000
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
```

---

## Part 9: Troubleshooting

| Issue | Solution |
|-------|----------|
| Milvus won't start | Check Docker/K8s logs, verify etcd/minio running |
| Search is slow | Build index, increase nprobe, use GPU if available |
| High memory usage | Reduce nlist, use partition pruning, release collections |
| Connection timeout | Verify host/port, check firewall, test connectivity |

---

## References

- Milvus Docs: https://milvus.io/docs
- Python SDK: https://milvus.io/docs/pymilvus-overview.md
- Index Types: https://milvus.io/docs/index.md
- Benchmarks: https://milvus.io/blog/2022-10-24-benchmark.md
