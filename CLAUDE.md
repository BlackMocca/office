# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**edoc-office** is a customized Docker-based build of ONLYOFFICE Document Server (v9.2). It is NOT a Go project — it's a containerized document editing/conversion service with custom Thai font support and editor modifications. Part of the larger **edoc** microservices ecosystem.

## Build & Development Commands

```bash
make build   # Build Docker image (tagged container-registry.innovasive.co.th/edoc/edoc-office:9.2.0-edoc-1)
make push    # Push image to container registry
make dev     # Run dev container locally on port 8089
```

## Architecture

- **Base image**: `onlyoffice/documentserver:9.3.1`
- **Core services inside container**:
  - CoAuthoring Service (port 8000) — real-time collaborative editing
  - FileConverter — document format conversion
  - Admin Panel (port 9000)
- **Stack**: Node.js (ONLYOFFICE internals), PostgreSQL, Redis, RabbitMQ
- **Protocol**: WOPI (Web Application Open Platform Interface)

## Key Files

- `Dockerfile` — custom image build adding Thai fonts (`fonts-thai-tlwg`, `fonts/THSarabun/`) and patches
- `config/default.json` — comprehensive ONLYOFFICE server configuration (DB, cache, queues, storage, JWT, WOPI)
- `patches/modified_file.js` — custom editor modifications, deployed to `/var/www/onlyoffice/documentserver/web-apps/apps/documenteditor/main/app/`
- `.env.example` — required environment variables (JWT, PostgreSQL, WOPI, Redis, fonts)

## Sibling Services

This project is one component of the edoc platform:
- `edoc-api` — main API
- `edoc-office-api` — office integration API
- `edoc-keycloak` — authentication
- `edoc-scheduler` — task scheduling
- `edoc-web-app` / `edoc-web-portal` — frontends

## Important Notes

- `.env` files, keys, and credentials are restricted from reading — do not attempt to access them
- AGPL-3.0 licensed; all modifications must be documented and patched separately
- Upstream source: https://github.com/ONLYOFFICE/DocumentServer
