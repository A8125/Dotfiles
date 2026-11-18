---
tags: [deployment, ollama, ngrok, server]
---

# Deployment

## Start Ngrok

```bash
ngrok http 11434
```

## Open Ollama

```bash
sudo pkill ollama && OLLAMA_HOST=0.0.0.0 OLLAMA_ORIGINS=* OLLAMA_MODELS=/var/lib/ollama/.ollama/models ollama serve
```

## Related
- [[Basic_Implementation]]
- [[Upvote_System]]