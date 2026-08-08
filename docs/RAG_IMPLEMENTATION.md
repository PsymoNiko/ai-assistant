# Retrieval-Augmented Generation (RAG) for ai-assistant

Complete guide for implementing RAG (Retrieval-Augmented Generation) using Qdrant vector database.

---

## Overview

RAG is a technique that enhances LLM responses by:
1. **Retrieving** relevant documents from a knowledge base
2. **Augmenting** the LLM prompt with retrieved context
3. **Generating** better informed responses

### Why RAG for ai-assistant?

Instead of relying only on the LLM's training data, RAG lets it answer questions about:
- Internal documentation and runbooks
- Operational procedures specific to your organization
- Past incident reports and resolutions
- System architecture and deployment guides
- Custom business logic and policies

---

## Architecture

```
User Query
    ↓
Embedding Model (from query)
    ↓
Qdrant Vector DB
    ↓ (Search similar)
Retrieved Documents
    ↓
LLM Prompt (with context)
    ↓
Enhanced Response
```

---

## Prerequisites

- Qdrant running (in docker-compose.yml at http://qdrant:6333)
- Embedding model (e.g., `sentence-transformers/all-MiniLM-L6-v2`)
- Document collection (markdown, PDFs, text files)
- Python libraries: `qdrant-client`, `sentence-transformers`

---

## Part 1: Setup

### 1. Docker Compose Update

Qdrant is already in `docker-compose.yml`:

```yaml
qdrant:
  image: qdrant/qdrant:latest
  container_name: qdrant
  ports:
    - "6333:6333"
  volumes:
    - qdrant_storage:/qdrant/storage
```

Verify running:

```bash
curl http://localhost:6333/health
# Should return: {"status":"ok"}
```

### 2. Install Python Dependencies

```bash
pip install qdrant-client sentence-transformers
```

### 3. Create Embeddings Module

Create `src/backend/rag/embeddings.py`:

```python
"""Embeddings using sentence-transformers"""

from sentence_transformers import SentenceTransformer
import numpy as np

class EmbeddingModel:
    def __init__(self, model_name: str = "sentence-transformers/all-MiniLM-L6-v2"):
        """Initialize embedding model"""
        self.model = SentenceTransformer(model_name)
        self.dimension = self.model.get_sentence_embedding_dimension()
    
    def embed_text(self, text: str) -> list:
        """Convert text to embedding vector"""
        embedding = self.model.encode(text, convert_to_numpy=True)
        return embedding.tolist()
    
    def embed_texts(self, texts: list) -> list:
        """Convert multiple texts to embeddings"""
        embeddings = self.model.encode(texts, convert_to_numpy=True)
        return embeddings.tolist()

# Example usage
if __name__ == "__main__":
    model = EmbeddingModel()
    text = "What is the deployment process?"
    embedding = model.embed_text(text)
    print(f"Embedding dimension: {len(embedding)}")
    print(f"First 5 values: {embedding[:5]}")
```

---

## Part 2: Vector Database

### Create Qdrant Collection

Create `src/backend/rag/qdrant_client.py`:

```python
"""Qdrant vector database client"""

from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct
from typing import List, Dict, Tuple
import uuid

class QdrantDB:
    def __init__(self, url: str = "http://qdrant:6333", collection_name: str = "ai-assistant-docs"):
        """Initialize Qdrant client"""
        self.client = QdrantClient(url=url)
        self.collection_name = collection_name
        self.dimension = 384  # MiniLM-L6-v2 dimension
        
        self._create_collection_if_not_exists()
    
    def _create_collection_if_not_exists(self):
        """Create collection if it doesn't exist"""
        try:
            self.client.get_collection(self.collection_name)
            print(f"Collection '{self.collection_name}' exists")
        except:
            self.client.create_collection(
                collection_name=self.collection_name,
                vectors_config=VectorParams(size=self.dimension, distance=Distance.COSINE),
            )
            print(f"Created collection '{self.collection_name}'")
    
    def add_document(self, text: str, metadata: Dict) -> str:
        """Add single document to collection"""
        from embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        embedding = model.embed_text(text)
        doc_id = str(uuid.uuid4())
        
        self.client.upsert(
            collection_name=self.collection_name,
            points=[
                PointStruct(
                    id=hash(doc_id) % (2**31),
                    vector=embedding,
                    payload={
                        "text": text,
                        "doc_id": doc_id,
                        **metadata
                    }
                )
            ]
        )
        return doc_id
    
    def add_documents(self, documents: List[Dict]) -> List[str]:
        """Add multiple documents
        
        Args:
            documents: List of dicts with 'text' and 'metadata' keys
        
        Example:
            documents = [
                {
                    "text": "Deployment procedure...",
                    "metadata": {"source": "deployment.md", "category": "operations"}
                }
            ]
        """
        from embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        texts = [doc["text"] for doc in documents]
        embeddings = model.embed_texts(texts)
        
        points = []
        doc_ids = []
        
        for i, (embedding, doc) in enumerate(zip(embeddings, documents)):
            doc_id = str(uuid.uuid4())
            doc_ids.append(doc_id)
            
            points.append(
                PointStruct(
                    id=hash(doc_id) % (2**31),
                    vector=embedding,
                    payload={
                        "text": doc["text"],
                        "doc_id": doc_id,
                        **doc.get("metadata", {})
                    }
                )
            )
        
        self.client.upsert(
            collection_name=self.collection_name,
            points=points
        )
        
        return doc_ids
    
    def search(self, query: str, limit: int = 5) -> List[Tuple[str, float]]:
        """Search for similar documents
        
        Returns:
            List of (document_text, similarity_score) tuples
        """
        from embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        query_embedding = model.embed_text(query)
        
        results = self.client.search(
            collection_name=self.collection_name,
            query_vector=query_embedding,
            limit=limit
        )
        
        return [
            (result.payload["text"], result.score)
            for result in results
        ]
    
    def search_with_metadata(self, query: str, limit: int = 5) -> List[Dict]:
        """Search and return full metadata"""
        from embeddings import EmbeddingModel
        
        model = EmbeddingModel()
        query_embedding = model.embed_text(query)
        
        results = self.client.search(
            collection_name=self.collection_name,
            query_vector=query_embedding,
            limit=limit
        )
        
        return [
            {
                "text": result.payload["text"],
                "score": result.score,
                "source": result.payload.get("source"),
                "category": result.payload.get("category"),
                "doc_id": result.payload.get("doc_id")
            }
            for result in results
        ]

# Example usage
if __name__ == "__main__":
    db = QdrantDB()
    
    # Add documents
    docs = [
        {
            "text": "To deploy the gateway, use: docker-compose up -d gateway",
            "metadata": {"source": "deployment.md", "category": "deployment"}
        },
        {
            "text": "Monitor CPU usage with: docker stats",
            "metadata": {"source": "monitoring.md", "category": "monitoring"}
        }
    ]
    
    doc_ids = db.add_documents(docs)
    print(f"Added {len(doc_ids)} documents")
    
    # Search
    results = db.search_with_metadata("How do I deploy?", limit=3)
    for r in results:
        print(f"Score: {r['score']:.2f} | {r['text'][:50]}...")
```

---

## Part 3: Document Ingestion

### Ingest from Markdown Files

Create `src/backend/rag/document_loader.py`:

```python
"""Load and ingest documents into vector database"""

import os
from pathlib import Path
from typing import List, Dict

class DocumentLoader:
    @staticmethod
    def load_markdown_files(directory: str, extension: str = ".md") -> List[Dict]:
        """Load markdown files from directory"""
        documents = []
        
        for file_path in Path(directory).glob(f"**/*{extension}"):
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Split by headings for better chunking
                chunks = DocumentLoader._chunk_by_heading(content)
                
                for i, chunk in enumerate(chunks):
                    if len(chunk.strip()) > 50:  # Ignore very small chunks
                        documents.append({
                            "text": chunk,
                            "metadata": {
                                "source": str(file_path.relative_to(directory)),
                                "category": file_path.parent.name,
                                "chunk_index": i
                            }
                        })
            except Exception as e:
                print(f"Error reading {file_path}: {e}")
        
        return documents
    
    @staticmethod
    def _chunk_by_heading(content: str, chunk_size: int = 500) -> List[str]:
        """Split content by headings and size"""
        chunks = []
        lines = content.split('\n')
        current_chunk = []
        
        for line in lines:
            current_chunk.append(line)
            
            # Create chunk if we hit a heading or size limit
            if (line.startswith('#') or 
                sum(len(l) for l in current_chunk) > chunk_size) and current_chunk:
                chunks.append('\n'.join(current_chunk))
                current_chunk = []
        
        if current_chunk:
            chunks.append('\n'.join(current_chunk))
        
        return chunks

# Example: Ingest documentation
if __name__ == "__main__":
    from qdrant_client import QdrantDB
    
    loader = DocumentLoader()
    
    # Load from docs directory
    docs = loader.load_markdown_files("docs/")
    print(f"Loaded {len(docs)} document chunks")
    
    # Add to Qdrant
    db = QdrantDB()
    db.add_documents(docs)
    print("Documents indexed!")
```

### Ingest Script

Create `scripts/ingest-docs.sh`:

```bash
#!/bin/bash
# Ingest documentation into Qdrant

python3 << 'EOF'
from src.backend.rag.document_loader import DocumentLoader
from src.backend.rag.qdrant_client import QdrantDB

# Load markdown files from docs, examples, and repository
loader = DocumentLoader()
all_docs = []

for directory in ["docs/", "examples/", "."]:
    docs = loader.load_markdown_files(directory)
    all_docs.extend(docs)
    print(f"Loaded {len(docs)} chunks from {directory}")

print(f"Total documents: {len(all_docs)}")

# Index in Qdrant
db = QdrantDB()
db.add_documents(all_docs)

print("✅ Documentation indexed in Qdrant!")
print(f"Collection: {db.collection_name}")
print(f"Dimension: {db.dimension}")

# Test search
results = db.search("How do I deploy?", limit=3)
print("\nTest search results:")
for text, score in results:
    print(f"  Score: {score:.2f} | {text[:50]}...")
EOF
```

---

## Part 4: LLM Integration

### Add RAG to n8n Workflow

Create n8n workflow: `03-rag-retrieval.json`

```json
{
  "name": "03 RAG Retrieval",
  "nodes": [
    {
      "id": "1",
      "name": "Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "parameters": {
        "path": "rag",
        "httpMethod": "POST"
      }
    },
    {
      "id": "2",
      "name": "Extract Query",
      "type": "n8n-nodes-base.set",
      "parameters": {
        "values": {
          "string": [
            {
              "name": "query",
              "value": "={{ $json.message }}"
            }
          ]
        }
      }
    },
    {
      "id": "3",
      "name": "Search Qdrant",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:8000/rag/search",
        "method": "POST",
        "body": {
          "query": "={{ $json.query }}",
          "limit": 5
        }
      }
    },
    {
      "id": "4",
      "name": "Format Context",
      "type": "n8n-nodes-base.functionItem",
      "parameters": {
        "functionCode": "const documents = items[0].json.results.map((r, i) => `[Doc ${i+1}] ${r.text}`).join('\\n\\n'); return {context: documents};"
      }
    },
    {
      "id": "5",
      "name": "Call LLM with RAG",
      "type": "n8n-nodes-base.openAi",
      "parameters": {
        "model": "local-llama",
        "prompt": "Use the following context to answer the question:\\n\\n{{ $json.context }}\\n\\nQuestion: {{ $json.query }}",
        "temperature": 0.7
      }
    },
    {
      "id": "6",
      "name": "Respond",
      "type": "n8n-nodes-base.respondToWebhook",
      "parameters": {
        "responseCode": 200
      }
    }
  ],
  "connections": {
    "1": {"2": [{"index": 0}]},
    "2": {"3": [{"index": 0}]},
    "3": {"4": [{"index": 0}]},
    "4": {"5": [{"index": 0}]},
    "5": {"6": [{"index": 0}]}
  }
}
```

### Add RAG Endpoint to Gateway

Add to `src/backend/gateway/app/main.py`:

```python
from src.backend.rag.qdrant_client import QdrantDB

qdrant_db = QdrantDB()

@app.post("/rag/search")
async def rag_search(query: str, limit: int = 5):
    """Search Qdrant for relevant documents"""
    try:
        results = qdrant_db.search_with_metadata(query, limit=limit)
        return {"results": results}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

@app.post("/rag/augment")
async def rag_augment_prompt(message: str, limit: int = 5):
    """Augment user message with retrieved context"""
    try:
        context_docs = qdrant_db.search(message, limit=limit)
        context = "\n\n".join([f"[Source: {source}]\n{text}" for text, score in context_docs])
        
        augmented_prompt = f"""Use the following context to answer the question:

{context}

Question: {message}"""
        
        return {
            "original_query": message,
            "context_documents": len(context_docs),
            "augmented_prompt": augmented_prompt
        }
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
```

---

## Part 5: Testing RAG

### Test Script

Create `scripts/test-rag.sh`:

```bash
#!/bin/bash

echo "Testing RAG pipeline..."

# Start services
docker-compose up -d

# Wait for services
sleep 10

# Test 1: Ingest documents
echo "1️⃣ Ingesting documentation..."
bash scripts/ingest-docs.sh

# Test 2: Search endpoint
echo "2️⃣ Testing search endpoint..."
curl -X POST http://localhost:8080/rag/search \
  -H "Content-Type: application/json" \
  -d '{"query": "How do I deploy?", "limit": 3}'

echo ""
echo "3️⃣ Testing augmented prompt..."
curl -X POST http://localhost:8080/rag/augment \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the deployment process?", "limit": 5}'

echo ""
echo "✅ RAG tests complete!"
```

---

## Part 6: Best Practices

### Document Preparation

✅ **DO:**
- Keep documents focused (one topic per document)
- Use clear headings and structure
- Include examples and code snippets
- Tag documents with metadata (category, version)

❌ **DON'T:**
- Mix too many topics in one document
- Use very long documents (chunk them)
- Store sensitive data (passwords, keys)
- Use only abbreviations without explanation

### RAG Quality Tips

1. **Semantic Search**: MiniLM embeddings work best for English technical documentation
2. **Chunk Size**: 300-500 tokens per chunk works well
3. **Metadata**: Tag documents by source, category, and version
4. **Filtering**: Use metadata filters for domain-specific searches
5. **Reranking**: For better results, rerank top-k results

### Monitoring RAG

Track:
- Search latency (should be < 200ms)
- Retrieval accuracy (does it return relevant docs?)
- LLM response quality (does RAG improve answers?)

---

## References

- Qdrant Docs: https://qdrant.tech/documentation/
- Sentence-Transformers: https://www.sbert.net/
- RAG Papers: https://arxiv.org/abs/2005.11401
- LLM Context Windows: https://huggingface.co/spaces/jondurbin/open-llm-leaderboard

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Qdrant not connecting | Check `http://qdrant:6333/health`, verify container running |
| Embedding slow | Pre-compute and cache embeddings, use GPU if available |
| Poor search results | Check document quality, adjust chunk size, try different embedding model |
| High memory usage | Reduce embedding model size, batch indexing, use sparse embeddings |

