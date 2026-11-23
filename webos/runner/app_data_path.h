#ifndef IPTV_WEBOS_APP_DATA_PATH_H_
#define IPTV_WEBOS_APP_DATA_PATH_H_

#include <cerrno>
#include <filesystem>
#include <system_error>
#include <unistd.h>

inline std::filesystem::path SelectAppDataHome(
    const std::filesystem::path& base, const std::filesystem::path& fallback,
    const std::filesystem::path& app_id) {
  const auto fallback_app = fallback / app_id;
  std::error_code error;
  if (std::filesystem::is_directory(fallback_app, error) &&
      access(fallback_app.c_str(), W_OK | X_OK) == 0) {
    return fallback;
  }

  error.clear();
  const auto primary_app = base / app_id;
  std::filesystem::create_directories(primary_app, error);
  const bool access_denied =
      error == std::errc::permission_denied ||
      (!error && access(primary_app.c_str(), W_OK | X_OK) != 0 &&
       errno == EACCES);
  if (access_denied && access(fallback.c_str(), W_OK | X_OK) == 0) {
    return fallback;
  }
  return base;
}

#endif