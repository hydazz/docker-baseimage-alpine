FROM alpine:edge as rootfs-stage

# environment
ARG TAG=latest
ENV REL=${TAG}
ENV MIRROR=http://dl-cdn.alpinelinux.org/alpine
ENV PACKAGES=alpine-baselayout,alpine-keys,apk-tools,busybox,libc-utils,xz

# install packages
RUN set -xe && \
	apk add --no-cache \
		bash \
		curl \
		tzdata \
		xz

RUN set -xe && \
	export ARCH=$(cat /etc/apk/arch) && \
	curl -o \
		/mkimage-alpine.bash -L \
		"https://raw.githubusercontent.com/gliderlabs/docker-alpine/master/builder/scripts/mkimage-alpine.bash" && \
	chmod +x \
		/mkimage-alpine.bash && \
	./mkimage-alpine.bash && \
	mkdir /root-out && \
	tar xf \
		/rootfs.tar.xz -C \
		/root-out && \
	sed -i -e 's/^root::/root:!:/' /root-out/etc/shadow

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# runtime stage
FROM scratch

COPY --from=rootfs-stage /root-out/ /

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
	HOME="/root" \
	TERM="xterm"

ARG OVERLAY_VERSION="v2.2.0.3"

RUN set -xe && \
	echo "**** install build packages ****" && \
	apk add --no-cache --virtual=build-dependencies \
		curl \
		patch \
		tar && \
	curl -o \
		/etc/apk/keys/hydaz.rsa.pub \
		"https://packages.hydenet.work/hydaz.rsa.pub" && \
	echo "https://packages.hydenet.work/alpine" >>/etc/apk/repositories && \
	echo "**** install runtime packages ****" && \
	apk add --no-cache \
		bash \
		ca-certificates \
		coreutils \
		procps \
		shadow \
		tzdata && \
	echo "**** install s6-overlay ****" && \
	if [ "$(arch)" = "x86_64" ]; then \
		OVERLAY_ARCH="amd64"; \
	elif echo "$(arch)" | grep -E -q "armv7l|aarch64"; then \
		OVERLAY_ARCH="arm"; \
	fi && \
	curl -o \
		/tmp/s6-overlay-installer -L \
		"https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}-installer" && \
	chmod +x /tmp/s6-overlay-installer && \
	/tmp/s6-overlay-installer "/" && \
	echo "**** patch s6-overlay ****" && \
	curl -o \
		/tmp/init-stage2.patch -L \
		"https://raw.githubusercontent.com/hydazz/docker-utils/main/patches/init-stage2.patch" && \
	echo "**** create abc user and make our folders ****" && \
	groupmod -g 1000 users && \
	useradd -u 911 -U -d /config -s /bin/false abc && \
	usermod -G users abc && \
	mkdir -p \
		/app \
		/config \
		/defaults && \
	mv /usr/bin/with-contenv /usr/bin/with-contenvb && \
	patch -u /etc/s6/init/init-stage2 -i /tmp/init-stage2.patch && \
	echo "**** cleanup ****" && \
	apk del --purge \
		build-dependencies && \
	rm -rf \
		/tmp/*

# add local files
COPY root/ /

ENTRYPOINT ["/init"]
