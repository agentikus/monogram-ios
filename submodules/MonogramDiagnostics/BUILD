load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MonogramDiagnostics",
    module_name = "MonogramDiagnostics",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [],
    visibility = [
        "//visibility:public",
    ],
)
