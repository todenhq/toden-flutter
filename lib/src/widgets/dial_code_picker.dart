import 'package:flutter/material.dart';

import '../config/country_names.g.dart';
import '../config/dial_codes.g.dart';
import '../config/id_types.dart' show countryLabel;
import '../config/theme.dart';
import 'dial_code_row.dart';
import 'dial_code_rows.dart';
import 'themed_sheet.dart';
import '../i18n/text_scope.dart';
import 'icons/icons.dart';

// ─── Country / dial-code picker ───────────────────────────────────────────────
//
// Country + international dialling code chooser for the phone field — and,
// with the dial column off, THE country picker (the key-people "where their
// ID was issued" field). One sheet for both, so the two feel identical.
// Presented through [showUiSheet] so it carries the SDK palette — a plain
// showModalBottomSheet lands on a sibling route where the theme extension isn't
// found, and renders light over a dark flow.
//
// Height is bounded against the space left ABOVE the keyboard: once someone
// taps into search, sizing against the full screen (as this used to) made the
// sheet effectively full-screen the moment the keys appeared — with the
// filtered results hidden underneath them.
//
// The list itself (the pinned geo row, the optional region headers) is built
// by dial_code_rows.dart; this file only renders it.

/// Opens the picker; resolves to the chosen ISO-2 code, or null if dismissed.
///
/// [pinned] is the visitor's IP country, lifted out of the alphabet to the top
/// of the list and tagged, so a guess we made on their behalf is visible AS a
/// guess and one tap away rather than buried among two hundred others.
///
/// [codes] narrows the list to the workflow's countries (null = every one).
Future<String?> showDialCodePicker(
  BuildContext context,
  String selected, {
  String? pinned,
  Iterable<String>? codes,
}) =>
    showUiSheet<String>(
      context,
      isScrollControlled: true,
      title: context.verificationText('contact.phone.codeTitle'),
      builder: (_) => _DialCodeSheet(selected: selected, pinned: pinned, codes: codes),
    );

/// Opens a plain country picker (no dial codes) — the SAME sheet as the phone
/// field's. Over every ISO country we can name, or a restricted [codes] subset
/// (a workflow's registry countries). [pinned] lifts the visitor's inferred
/// country to the top as "Your location"; [grouped] lists the rest under
/// region headers, the country-select step's way (the address-scope country
/// control asks for both).
///
/// [copy] words the sheet in the caller's own text group and, when given,
/// also pins the current answer above the visitor's own, tagged
/// [CountryPickerCopy.selected]: the country summary row's sheet.
Future<String?> showCountryPicker(
  BuildContext context,
  String? selected, {
  Iterable<String>? codes,
  String? pinned,
  bool grouped = false,
  CountryPickerCopy? copy,
  String? title,
}) =>
    showUiSheet<String>(
      context,
      isScrollControlled: true,
      title: title,
      builder: (_) => _DialCodeSheet(
        selected: selected ?? '',
        showDial: false,
        codes: codes,
        pinned: pinned,
        grouped: grouped,
        copy: copy,
      ),
    );

/// The words the country sheet shows, from the caller's own text group.
class CountryPickerCopy {
  final String search;
  final String noMatches;
  final String selected;
  final String yourLocation;
  const CountryPickerCopy({
    required this.search,
    required this.noMatches,
    required this.selected,
    required this.yourLocation,
  });
}

class _DialCodeSheet extends StatefulWidget {
  final String selected;

  /// False ⇒ plain country picker: every named country, no dial column.
  final bool showDial;

  /// Restricts the country list (plain picker only). Null ⇒ all named ISO.
  final Iterable<String>? codes;

  /// The visitor's IP country, pinned to the top (still subject to search).
  final String? pinned;

  /// Region headers between the rows (the pinned row stays on top).
  final bool grouped;

  /// The caller's words; also pins the current answer (see showCountryPicker).
  final CountryPickerCopy? copy;

  const _DialCodeSheet({
    required this.selected,
    this.showDial = true,
    this.codes,
    this.pinned,
    this.grouped = false,
    this.copy,
  });

  @override
  State<_DialCodeSheet> createState() => _DialCodeSheetState();
}

class _DialCodeSheetState extends State<_DialCodeSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final media = MediaQuery.of(context);
    final q = _query.trim().toLowerCase();

    final codes = widget.showDial
        ? (widget.codes?.where(kDialCodes.containsKey) ?? kDialCodes.keys)
        : (widget.codes ?? kCountryNames.keys);
    final entries = codes
        .map<DialCodeEntry>((iso) => (
              iso: iso,
              name: countryLabel(iso),
              dial: widget.showDial ? kDialCodes[iso]! : '',
            ))
        .where((e) =>
            q.isEmpty ||
            e.name.toLowerCase().contains(q) ||
            (widget.showDial && e.dial.contains(q)) ||
            e.iso.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final copy = widget.copy;
    final items = buildDialCodeItems(
      entries,
      widget.pinned,
      grouped: widget.grouped,
      pinSelected: copy != null && widget.selected.isNotEmpty ? widget.selected : null,
    );

    // Space actually available above the keyboard, then capped so the sheet
    // stays a sheet rather than swallowing the screen.
    final available = media.size.height - media.viewInsets.bottom;
    final maxHeight = (available * 0.85).clamp(240.0, media.size.height * 0.6);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _searchRow(
                copy?.search ??
                    (widget.showDial ? 'Search country or code' : 'Search country'),
              ),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(UiSpacing.lg),
                        child: Text(copy?.noMatches ?? 'No countries match your search.',
                            style: text.bodyMedium),
                      )
                    : ListView.builder(
                        // The web list's p-1.5, and pb-6 so the last row
                        // clears the sheet's rounded bottom edge.
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, UiSpacing.lg),
                        itemCount: items.length,
                        itemBuilder: (_, i) => switch (items[i]) {
                          DialCodeHeaderItem(:final region) =>
                            DialCodeRegionHeader(region: region),
                          DialCodeRowItem(:final entry, :final pinned, :final selectedPin) =>
                            _row(entry, pinned, selectedPin,
                                lastPin: pinned &&
                                    (i + 1 >= items.length ||
                                        items[i + 1] is! DialCodeRowItem ||
                                        !(items[i + 1] as DialCodeRowItem).pinned),
                                count: items.length),
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The web sheet's search: no box, a 44px row ruled off underneath, and a
  /// clear button once something is typed.
  Widget _searchRow(String hint) {
    final colors = context.myazaColors;
    final style = context.myazaText.input;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          UiIcon(UiIcons.search, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            // Deliberately NOT autofocused: springing the keyboard the
            // instant the sheet opens hides half the list before the
            // person has even seen it - search is one tap away.
            child: TextField(
              controller: _search,
              autocorrect: false,
              style: style,
              cursorColor: colors.primary,
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: style.copyWith(color: colors.textMuted),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_query.isNotEmpty)
            Semantics(
              button: true,
              label: 'Clear',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: UiIcon(UiIcons.x, size: 14, color: colors.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(DialCodeEntry e, bool isPinned, bool selectedPin,
      {required bool lastPin, required int count}) {
    final copy = widget.copy;
    final row = DialCodeRow(
      iso: e.iso,
      name: e.name,
      dial: e.dial,
      isSelected: e.iso == widget.selected,
      badge: !isPinned
          ? null
          : selectedPin
              ? (copy?.selected ?? 'Selected')
              : (copy?.yourLocation ?? 'Your location'),
      onTap: () => Navigator.of(context).pop(e.iso),
    );
    // A hairline under the pinned rows only: the list below them is one list,
    // and a rule between every row is noise.
    if (!isPinned || !lastPin || count == 1) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row, const DialCodeDivider()],
    );
  }
}
