# Lua 5.1, the version the WoW client embeds, with busted and luacov.
FROM alpine:3.20
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 build-base \
	&& luarocks-5.1 install busted 2.3.0-1 \
	&& luarocks-5.1 install luacov 0.17.0-1
WORKDIR /src
CMD ["sh", "spec/run.sh"]
