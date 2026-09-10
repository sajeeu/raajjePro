import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_theme.dart';

/// Whether a field has to be filled in, said as a word on its label row.
///
/// 🔧 **Added in Phase 6a** — flagged rather than done silently, because this
/// is shared Phase 1 code. Every form in the delivered prototypes marks its
/// fields this way (`Become a Provider.dc.html`, `Create Service.dc.html`,
/// `Register.dc.html`), and §Phase 6a's step 2 is the first screen built
/// against one of them. Phase 9's wizard renders the same pills, so the copy
/// and the two tints belong here rather than in either screen.
///
/// **A word rather than an asterisk.** `*` is a convention a first-time
/// provider has to already know, and it is invisible to a screen reader
/// unless something spells it out — [AppTextField] appends this to the spoken
/// label for exactly that reason.
enum FieldRequirement {
  /// Renders "Required" in the accent tint.
  mandatory('Required'),

  /// Renders "Optional" in the neutral tint. Worth stating: §Phase 6a marks
  /// the photo and the introduction optional, and a provider who cannot tell
  /// fills in everything or abandons the form.
  optional('Optional');

  const FieldRequirement(this.label);

  /// The visible word, and what a screen reader hears after the field's name.
  final String label;
}

/// The pill itself, for a control that is not an [AppTextField] — a chooser, a
/// picker, a card pair. Text fields take a `requirement` instead and draw this
/// themselves.
class FieldRequirementPill extends StatelessWidget {
  const FieldRequirementPill(this.requirement, {super.key});

  final FieldRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fill, ink) = switch (requirement) {
      FieldRequirement.mandatory => (colors.accentTint, colors.primary),
      FieldRequirement.optional => (colors.neutralTint, colors.textSecondary),
    };

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs / 2 + 1,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppRadius.circular(AppRadius.pill),
      ),
      child: Text(
        requirement.label,
        style: context.type.pill.copyWith(color: ink),
      ),
    );
  }
}
