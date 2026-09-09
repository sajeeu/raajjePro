import 'package:flutter/material.dart';

/// Resolves a category's seeded `iconIdentifier` to a glyph.
///
/// The same shape as [CategoryAccents] next door, and for the same reason:
/// a category is seeded with an *identifier*, not an asset, so a thirteenth
/// added through the API after this build shipped still draws something
/// sensible instead of throwing or leaving a hole in the grid (§Phase 4
/// Done-when).
///
/// **A deliberate divergence from the prototypes**, recorded here rather than
/// left to be rediscovered: `Discovery.dc.html` draws each tile from a bespoke
/// SVG path. This app has no SVG renderer and Phase 1 built the whole design
/// system on Material glyphs (`AppHeader`, `EmptyState`, `AnimatedBottomNav`
/// all take `IconData`), so the twelve resolve to the closest Material icon
/// rather than to the prototype's own outline. Shape, weight and size differ
/// slightly; hue, tile geometry and label do not. Adding an SVG dependency
/// for twelve glyphs was judged the worse trade — flagged for the design
/// project rather than settled unilaterally.
abstract final class CategoryIcons {
  /// Keyed by the identifier the seed writes, never by category name.
  static const Map<String, IconData> byIdentifier = {
    'sparkle': Icons.auto_awesome_outlined, // Cleaning
    'droplet': Icons.water_drop_outlined, // Plumbing
    'bolt': Icons.bolt_outlined, // Electrical
    'wind': Icons.air_outlined, // AC Repair
    'heart': Icons.favorite_outline, // Beauty
    'camera': Icons.photo_camera_outlined, // Photography
    'bug': Icons.pest_control_outlined, // Pest Control
    'appliance': Icons.local_laundry_service_outlined, // Appliance Repair
    'box': Icons.inventory_2_outlined, // Moving
    'dumbbell': Icons.fitness_center_outlined, // Fitness
    'hammer': Icons.handyman_outlined, // Home Repairs
    'boat': Icons.sailing_outlined, // Boat Charter
  };

  /// For an identifier this build does not know. Neutral and generic, so it
  /// never impersonates another category — the same rule
  /// [CategoryAccents.fallback] follows.
  static const IconData fallback = Icons.category_outlined;

  static IconData resolve(String? identifier) =>
      byIdentifier[identifier] ?? fallback;
}
