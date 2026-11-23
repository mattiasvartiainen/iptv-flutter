// Copyright (c) 2026 LG Electronics, Inc. All rights reserved.
// Copyright 2021 Sony Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <flutter_window.h>

#include <cstdlib>
#include <filesystem>

#include "app_data_path.h"
#include "flutter/generated_plugin_registrant.h"

class App : public FlutterWindow {
 public:
  void OnOptionsParsed() override {
    const char* base = std::getenv("FLUTTER_APPDATA_HOME");
    const char* app_id = std::getenv("FLUTTER_APP_ID");
    const char* bundle = std::getenv("FLUTTER_BUNDLE_PATH");
    if (!base || !*base || !app_id || !*app_id || !bundle || !*bundle) return;

    const auto fallback = std::filesystem::path(bundle) / ".dart_tool" /
                          "sqflite_common_ffi" / "databases";
    const auto selected = SelectAppDataHome(base, fallback, app_id);
    if (selected != base) {
      setenv("FLUTTER_APPDATA_HOME", selected.c_str(), 1);
    }
  }

  bool OnCreate() override {
    if (!FlutterWindow::OnCreate()) return false;
    RegisterPlugins(GetRegistrar());
    return true;
  }
};

int main(int argc, char** argv) {
  App app;
  return app.Run(argc, argv);
}
