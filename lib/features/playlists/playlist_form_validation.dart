String? validatePlaylistName(String? value) =>
    value == null || value.trim().isEmpty ? 'Enter a playlist name.' : null;

String? validatePlaylistUrl(String? value) =>
    value == null ||
        Uri.tryParse(value.trim()) == null ||
        !Uri.tryParse(value.trim())!.hasScheme
    ? 'Enter a valid playlist URL.'
    : null;

String? validateXtreamServer(String? value) =>
    value == null || value.trim().isEmpty ? 'Enter the server URL.' : null;

String? validateXtreamUsername(String? value) =>
    value == null || value.trim().isEmpty ? 'Enter the username.' : null;

String? validateXtreamPassword(String? value) =>
    value == null || value.isEmpty ? 'Enter the password.' : null;
