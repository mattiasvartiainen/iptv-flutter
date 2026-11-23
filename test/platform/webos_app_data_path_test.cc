#include "../../webos/runner/app_data_path.h"

#include <cassert>
#include <cstdlib>

int main() {
  char temporary[] = "/tmp/iptv-webos-path-XXXXXX";
  const char* created = mkdtemp(temporary);
  assert(created != nullptr);
  const std::filesystem::path root(created);
  const auto base = root / "appdata";
  const auto fallback = root / "databases";
  const auto app_id = std::filesystem::path("com.example.app");
  std::filesystem::create_directories(base);
  std::filesystem::create_directories(fallback);

  assert(SelectAppDataHome(base, fallback, app_id) == base);
  assert(std::filesystem::is_directory(base / app_id));

  std::filesystem::permissions(base / app_id,
                               std::filesystem::perms::owner_read |
                                   std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::replace);
  assert(SelectAppDataHome(base, fallback, app_id) == fallback);
  std::filesystem::create_directories(fallback / app_id);
  std::filesystem::permissions(base / app_id,
                               std::filesystem::perms::owner_all,
                               std::filesystem::perm_options::replace);
  assert(SelectAppDataHome(base, fallback, app_id) == fallback);

  const auto denied_base = root / "denied";
  std::filesystem::create_directories(denied_base);
  std::filesystem::permissions(denied_base,
                               std::filesystem::perms::owner_read |
                                   std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::replace);
  assert(SelectAppDataHome(denied_base, fallback, "other-app") == fallback);
  std::filesystem::permissions(denied_base,
                               std::filesystem::perms::owner_all,
                               std::filesystem::perm_options::replace);
  std::filesystem::remove_all(root);
}