load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramVoip",
    module_name = "TelegramVoip",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/TgVoip:TgVoip",
        "//submodules/TgVoipWebrtc:TgVoipWebrtc",
    ],
    visibility = [
        "//visibility:public",
    ],
)
