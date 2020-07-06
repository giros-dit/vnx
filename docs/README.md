# Build docs

Use `squidfunk/mkdocs-material` Docker image to build docs using [Material for Mkdocs template](https://squidfunk.github.io/mkdocs-material/). Following command launches a web server for a real-time development of the documentation:

```bash
docker run --rm -it -p 8000:8000 -v ${PWD}/../:/docs squidfunk/mkdocs-material
```

