package = "ztgw"
version = "0.1-0"
supported_platforms = {"linux"}

source = {
    url = "git://github.com/jixindatech/ztgw",
    tag = "v0.10",
    branch="dev",
}

description = {
    summary = "zero trust gateway.",
    homepage = "https://github.com/jixindatech/ztgw",
    maintainer = "Fangang Cheng <chengfangang@qq.com>"
}

dependencies = {
    "lua-tinyyaml = 1.0",
    "lua-resty-logger-socket = 2.0",
    "lua-resty-kafka = 0.09",
}

build = {
    type = "make",
    build_variables = {
        CFLAGS="$(CFLAGS)",
        LIBFLAG="$(LIBFLAG)",
        LUA_LIBDIR="$(LUA_LIBDIR)",
        LUA_BINDIR="$(LUA_BINDIR)",
        LUA_INCDIR="$(LUA_INCDIR)",
        LUA="$(LUA)",
    },
    install_variables = {
        INST_PREFIX="$(PREFIX)",
        INST_BINDIR="$(BINDIR)",
        INST_LIBDIR="$(LIBDIR)",
        INST_LUADIR="$(LUADIR)",
        INST_CONFDIR="$(CONFDIR)",
    },
}
