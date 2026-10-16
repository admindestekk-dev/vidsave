import 'package:photo_manager/photo_manager.dart';

abstract interface class MediaLibrary {
  Future<PermissionState> requestPermission();

  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  });

  /// Clears cached asset paths so newly scanned/downloaded files appear.
  void invalidateCache();
}

class PhotoManagerMediaLibrary implements MediaLibrary {
  final Map<int, AssetPathEntity> _allMediaPaths = {};

  @override
  void invalidateCache() {
    _allMediaPaths.clear();
    PhotoManager.clearFileCache();
  }

  @override
  Future<PermissionState> requestPermission() {
    return PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.video + RequestType.audio,
          mediaLocation: false,
        ),
      ),
    );
  }

  @override
  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  }) async {
    var path = _allMediaPaths[type.value];
    path ??= await _findAllMediaPath(type);
    if (path == null) {
      return [];
    }

    _allMediaPaths[type.value] = path;
    return path.getAssetListPaged(page: page, size: pageSize);
  }

  Future<AssetPathEntity?> _findAllMediaPath(RequestType type) async {
    // First try onlyAll: true (the default "Recent/All" virtual album)
    var paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: type,
      filterOption: FilterOptionGroup(
        videoOption: const FilterOption(needTitle: true),
        audioOption: const FilterOption(needTitle: true),
        orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (paths.isNotEmpty) return paths.first;

    // Fallback: try all albums (e.g. "Download", "Movies", "Music")
    paths = await PhotoManager.getAssetPathList(
      onlyAll: false,
      type: type,
      filterOption: FilterOptionGroup(
        videoOption: const FilterOption(needTitle: true),
        audioOption: const FilterOption(needTitle: true),
        orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    return paths.isNotEmpty ? paths.first : null;
  }
}
