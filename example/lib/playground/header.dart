import 'package:flutter/material.dart';

import 'devices.dart';
import 'open_url.dart' if (dart.library.js_interop) 'open_url_web.dart';

/// A button in the header for the device on show.
@immutable
class HeaderAction {
  const HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;

  /// `null` while it cannot be used, as during a fold.
  final VoidCallback? onTap;
  final bool primary;
}

const Color _ink = Color(0xFF17171C);
const Color _muted = Color(0xFF6B6B76);
const Color _line = Color(0xFFE6E6EE);

/// The full-width bar across the top of the playground.
class PlaygroundHeader extends StatelessWidget {
  const PlaygroundHeader({
    super.key,
    required this.device,
    required this.onDevice,
    required this.actions,
  });

  final Device device;

  /// `null` while switching is not possible.
  final ValueChanged<Device>? onDevice;
  final List<HeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    final Widget tabs = _DeviceTabs(selected: device, onSelect: onDevice);
    final Widget buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (int i, HeaderAction a) in actions.indexed) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          _ActionButton(action: a),
        ],
      ],
    );
    const Widget links = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Link(label: 'pub.dev', url: 'https://pub.dev/packages/adaptive_nav'),
        SizedBox(width: 4),
        _Link(
          label: 'GitHub',
          url: 'https://github.com/nightdevcraft/adaptive_nav',
        ),
      ],
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Widget trailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  buttons,
                  if (actions.isNotEmpty) const _Divider(),
                  links,
                ],
              );
              // Room for the switcher dead centre: each side gets as much as
              // the wider of them needs.
              if (c.maxWidth >= 1560) {
                return Row(
                  children: <Widget>[
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Brand(),
                      ),
                    ),
                    tabs,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: trailing,
                        ),
                      ),
                    ),
                  ],
                );
              }
              // One row still fits, with the switcher off centre.
              if (c.maxWidth >= 1200) {
                return Row(
                  children: <Widget>[
                    const Flexible(child: _Brand()),
                    const SizedBox(width: 24),
                    const Spacer(),
                    tabs,
                    const SizedBox(width: 16),
                    trailing,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Expanded(child: _Brand()),
                      links,
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        tabs,
                        const SizedBox(width: 12),
                        buttons,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'adaptive_nav',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 1),
              Text(
                'One navigation state · stack or master-detail',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceTabs extends StatelessWidget {
  const _DeviceTabs({required this.selected, required this.onSelect});

  final Device selected;
  final ValueChanged<Device>? onSelect;

  static const List<(Device, IconData, String)> _tabs =
      <(Device, IconData, String)>[
        (Device.desktop, Icons.desktop_windows_outlined, 'Desktop'),
        (Device.phone, Icons.smartphone, 'Phone'),
        (Device.tablet, Icons.tablet_mac, 'Tablet'),
        (Device.duo, Icons.devices_fold, 'iPhone Duo'),
        (Device.galaxyFold, Icons.menu_book_outlined, 'Galaxy Z Fold8'),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (Device d, IconData icon, String label) in _tabs)
            _Tab(
              icon: icon,
              label: label,
              selected: d == selected,
              onTap: onSelect == null ? null : () => onSelect!(d),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color fg = selected ? primary : _muted;
    return MouseRegion(
      cursor: onTap == null || selected
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _ink : _muted,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final HeaderAction action;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool enabled = action.onTap != null;
    final Color fg = action.primary ? Colors.white : _ink;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: action.primary ? primary : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: action.primary
              ? BorderSide.none
              : const BorderSide(color: _line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(action.icon, size: 17, color: fg),
                const SizedBox(width: 8),
                Text(
                  action.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: _line,
  );
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => openUrl(url),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.north_east, size: 14, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}
