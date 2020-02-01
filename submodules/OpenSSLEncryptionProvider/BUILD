load(
    "@rules_apple_extras//apple:objc_library.bzl",
    "objc_library",
)

objc_library(
    name = "OpenSSLEncryptionProvider",
    srcs = glob([
        "Sources/**/*.m",
    ]),
    hdrs = glob([
        "Sources/**/*.h",
    ]),
    deps = [
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/openssl:openssl",
    ],
    visibility = ["//visibility:public"],
)
