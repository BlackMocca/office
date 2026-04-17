# ThaiDistributed Document Server

*(Based on ONLYOFFICE Community Edition)*

A customized build of ONLYOFFICE Document Server, maintained and extended by **ThaiDistributed**.

---

## 🚀 Features

* **Client-side document editor**
  Web-based Word-like editor for real-time document editing

* **Server-side document processing**
  High-performance engine for document conversion, rendering, and file handling

* **Docker-ready build**
  Easily build and deploy using containerized environments

---

## 📦 Base Image

* Image: `onlyoffice/documentserver`
* Version: `9.3.1`
* License: AGPL-3.0

Upstream source code:
https://github.com/ONLYOFFICE/DocumentServer

---

## 🏢 About ThaiDistributed

**ThaiDistributed** is responsible for:

* Customizing and maintaining this build
* Adding integrations and enhancements
* Managing deployment and distribution

---

## 🔧 Modifications

The following files have been modified from the upstream source:

* `/var/www/onlyoffice/documentserver/web-apps/apps/documenteditor/main/app/modified_file.js`

> Additional modifications may be applied as part of ongoing development.

---

## 🛠️ Build Instructions

To build the custom Docker image:

```bash
make build
```

---

## 📜 License

This project complies with the terms of the **GNU AGPL v3** license.

* Source code modifications are provided as required by AGPL
* If you distribute this software or provide it as a network service, you must also provide access to the source code

---

## ⚠️ Trademark Notice

* ONLYOFFICE is a registered trademark of Ascensio System SIA
* This project is **not affiliated with or endorsed by ONLYOFFICE**
* All original branding, logos, and trademarks belong to their respective owners

---

## 🙌 Acknowledgements

This project is based on the open-source work of the ONLYOFFICE team.

---

**ThaiDistributed Platform — Powered by ONLYOFFICE**
