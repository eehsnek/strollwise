/// Map layer toggles persisted in [layerSettingsProvider].
class LayerSettings {
  const LayerSettings({
    /// Zone polygon fill from traveler mix (who).
    this.showTravelerLayer = true,
    /// Catalog place outlines by place type (what).
    this.showFunctionalOverlay = true,
    this.showHeatmap = false,
    this.showTraffic = false,
    this.showFeedMarkers = true,
    this.opacity = 0.8,
  });

  final bool showTravelerLayer;
  final bool showFunctionalOverlay;
  final bool showHeatmap;
  final bool showTraffic;
  final bool showFeedMarkers;
  final double opacity;

  LayerSettings copyWith({
    bool? showTravelerLayer,
    bool? showFunctionalOverlay,
    bool? showHeatmap,
    bool? showTraffic,
    bool? showFeedMarkers,
    double? opacity,
  }) {
    return LayerSettings(
      showTravelerLayer: showTravelerLayer ?? this.showTravelerLayer,
      showFunctionalOverlay:
          showFunctionalOverlay ?? this.showFunctionalOverlay,
      showHeatmap: showHeatmap ?? this.showHeatmap,
      showTraffic: showTraffic ?? this.showTraffic,
      showFeedMarkers: showFeedMarkers ?? this.showFeedMarkers,
      opacity: opacity ?? this.opacity,
    );
  }
}
