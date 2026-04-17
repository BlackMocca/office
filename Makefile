# ===============================
# Config
# ===============================

REGISTRY := blackmocca
IMAGE_NAME := office
IMAGE_TAG := 9.3.1-office

FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

SDKJS_REPO := https://github.com/BlackMocca/sdkjs.git
WEB_APPS_REPO := https://github.com/BlackMocca/web-apps.git
BUILD_TOOLS_REPO := https://github.com/BlackMocca/build_tools.git
CORE_REPO := https://github.com/BlackMocca/core.git

# ===============================
# Setup: clone required repos
# ===============================

.PHONY: setup
setup:
	@if [ ! -f core/Readme.md ]; then rm -rf core && git clone $(CORE_REPO) core; fi
	@if [ ! -f sdkjs/package.json ]; then rm -rf sdkjs && git clone $(SDKJS_REPO) sdkjs; fi
	@if [ ! -f web-apps/package.json ]; then rm -rf web-apps && git clone $(WEB_APPS_REPO) web-apps; fi
	@if [ ! -f build_tools/configure.py ]; then rm -rf build_tools && git clone $(BUILD_TOOLS_REPO) build_tools; fi
	@echo "Setup complete."

# ===============================
# Build JS only (sdkjs + web-apps)
# ===============================

.PHONY: build-js
build-js:
	docker build --no-cache --target js-builder -t edoc-js-builder .
	docker create --name js-tmp edoc-js-builder
	mkdir -p dist/sdkjs/word dist/web-apps
	docker cp js-tmp:/build/sdkjs/deploy/sdkjs/word/ dist/sdkjs/word/
	docker cp js-tmp:/build/web-apps/deploy/web-apps/ dist/web-apps/
	docker rm js-tmp
	@echo "Build output: dist/"

# ===============================
# Build final image
# ===============================

.PHONY: build
build:
	docker build --no-cache -t $(FULL_IMAGE) .

# ===============================
# Push
# ===============================

.PHONY: push
push:
	docker push $(FULL_IMAGE)

# ===============================
# Dev
# ===============================

.PHONY: dev
dev:
	docker rm -f office
	docker run -d \
		--name office \
		--restart unless-stopped \
		--env-file .env \
		-p 8089:80 \
		$(FULL_IMAGE)
