import 'dart:ui' as ui;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/address_book.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/my_group.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as mod_menu;
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:pull_down_button/pull_down_button.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

class PeerTabPage extends StatefulWidget {
  const PeerTabPage({Key? key}) : super(key: key);
  @override
  State<PeerTabPage> createState() => _PeerTabPageState();
}

class _TabEntry {
  final Widget widget;
  final Function({dynamic hint})? load;
  _TabEntry(this.widget, [this.load]);
}

EdgeInsets? _menuPadding() {
  if (isDesktop || isWebDesktop) {
    return kDesktopMenuPadding;
  }
  // 모바일: null 반환하여 mod_menu.PopupMenuItem 기본 패딩(16.0) 사용
  // Mobile: return null to use mod_menu.PopupMenuItem default padding (16.0)
  return null;
}

class _PeerTabPageState extends State<PeerTabPage>
    with SingleTickerProviderStateMixin {
  final List<_TabEntry> entries = [
    _TabEntry(RecentPeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(FavoritePeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(DiscoveredPeersView(
      menuPadding: _menuPadding(),
    )),
    // AddressBook and MyGroup tabs removed
    _TabEntry(Container(), null), // placeholder for index 3
    _TabEntry(Container(), null), // placeholder for index 4
  ];
  RelativeRect? mobileTabContextMenuPos;

  final isOptVisiableFixed = isOptionFixed(kOptionPeerTabVisible);

  _PeerTabPageState() {
    _loadLocalOptions();
  }

  void _loadLocalOptions() {
    final uiType = bind.getLocalFlutterOption(k: kOptionPeerCardUiType);
    if (uiType != '') {
      peerCardUiType.value = int.parse(uiType) == 0
          ? PeerUiType.grid
          : int.parse(uiType) == 1
              ? PeerUiType.tile
              : PeerUiType.list;
    }
    hideAbTagsPanel.value =
        bind.mainGetLocalOption(key: kOptionHideAbTagsPanel) == 'Y';
  }

  Future<void> handleTabSelection(int tabIndex) async {
    if (tabIndex < entries.length) {
      if (tabIndex != gFFI.peerTabModel.currentTab) {
        gFFI.peerTabModel.setCurrentTabCachedPeers([]);
      }
      gFFI.peerTabModel.setCurrentTab(tabIndex);
      entries[tabIndex].load?.call(hint: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      textBaseline: TextBaseline.ideographic,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(builder: (context) {
          final tabTheme = MyTheme.peerTab(context);
          return Obx(() => SizedBox(
                height: isMobile ? 42 : tabTheme.height,
                child: Container(
                  padding: stateGlobal.isPortrait.isTrue
                      ? EdgeInsets.symmetric(horizontal: 2)
                      : null,
                  child: peerSearchExpanded.value
                      ? const PeerSearchBar()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                                child: visibleContextMenuListener(
                                    _createSwitchBar(context))),
                            if (stateGlobal.isPortrait.isTrue)
                              ..._portraitRightActions(context)
                            else
                              ..._landscapeRightActions(context)
                          ],
                        ),
                ),
              ).paddingOnly(
                  left: stateGlobal.isPortrait.isTrue ? 0 : 16,
                  right: stateGlobal.isPortrait.isTrue ? 0 : 16));
        }),
        if (isMobile) const SizedBox(height: 20), // 피어탭과 피어카드 사이 간격
        _createPeersView(),
      ],
    );
  }

  Widget _createSwitchBar(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final tabKeys = ['Recent sessions', 'Favorites', 'Discovered'];
    final theme = MyTheme.peerTab(context);

    return Row(
      children: model.visibleEnabledOrderedIndexs.map((t) {
        final selected = model.currentTab == t;
        final label = t < tabKeys.length ? translate(tabKeys[t]) : 'Tab $t';
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: isOptionFixed(kOptionPeerTabIndex)
                ? null
                : () async {
                    await handleTabSelection(t);
                    await bind.setLocalFlutterOption(
                        k: kOptionPeerTabIndex, v: t.toString());
                  },
            child: Container(
              height: isMobile ? null : theme.height,
              padding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                  : EdgeInsets.symmetric(horizontal: theme.horizontalPadding),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF2F2E31)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(isMobile ? 8 : theme.borderRadius),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? theme.selectedTextColor
                      : theme.unselectedTextColor,
                  fontSize: isMobile ? 14 : theme.fontSize,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _createPeersView() {
    final model = Provider.of<PeerTabModel>(context);
    Widget child;
    if (model.visibleEnabledOrderedIndexs.isEmpty) {
      child = visibleContextMenuListener(Row(
        children: [Expanded(child: InkWell())],
      ));
    } else {
      if (model.visibleEnabledOrderedIndexs.contains(model.currentTab)) {
        child = entries[model.currentTab].widget;
      } else {
        debugPrint("should not happen! currentTab not in visibleIndexs");
        Future.delayed(Duration.zero, () {
          model.setCurrentTab(model.visibleEnabledOrderedIndexs[0]);
        });
        child = entries[0].widget;
      }
    }
    return Expanded(
        child: child.marginSymmetric(
            vertical: (isDesktop || isWebDesktop) ? 12.0 : 6.0));
  }

  Widget _createRefresh(
      {required PeerTabIndex index, required RxBool loading}) {
    final model = Provider.of<PeerTabModel>(context);
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Offstage(
      offstage: model.currentTab != index.index,
      child: Tooltip(
        message: translate('Refresh'),
        child: RefreshWidget(
            onPressed: () {
              if (gFFI.peerTabModel.currentTab < entries.length) {
                entries[gFFI.peerTabModel.currentTab].load?.call();
              }
            },
            spinning: loading,
            child: RotatedBox(
                quarterTurns: 2,
                child: Icon(
                  Icons.refresh,
                  size: 18,
                  color: textColor,
                ))),
      ),
    );
  }

  Widget _createPeerViewTypeSwitch(BuildContext context) {
    return PeerViewDropdown();
  }

  Widget _createMultiSelection() {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
      toolTip: translate('Select'),
      context: context,
      onTap: () {
        model.setMultiSelectionMode(true);
        if (isMobile && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: SvgPicture.asset(
        "assets/checkbox-outline.svg",
        width: 18,
        height: 18,
        colorFilter: svgColor(textColor),
      ),
    );
  }

  void mobileShowTabVisibilityMenu() {
    final model = gFFI.peerTabModel;
    final items = List<PopupMenuItem>.empty(growable: true);
    for (int i = 0; i < PeerTabModel.maxTabCount; i++) {
      if (!model.isEnabled[i]) continue;
      items.add(PopupMenuItem(
        height: kMinInteractiveDimension * 0.8,
        onTap: isOptVisiableFixed
            ? null
            : () => model.setTabVisible(i, !model.isVisibleEnabled[i]),
        enabled: !isOptVisiableFixed,
        child: Row(
          children: [
            Checkbox(
                value: model.isVisibleEnabled[i],
                onChanged: isOptVisiableFixed
                    ? null
                    : (_) {
                        model.setTabVisible(i, !model.isVisibleEnabled[i]);
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      }),
            Expanded(child: Text(model.tabTooltip(i))),
          ],
        ),
      ));
    }
    if (mobileTabContextMenuPos != null) {
      showMenu(
          context: context, position: mobileTabContextMenuPos!, items: items);
    }
  }

  Widget visibleContextMenuListener(Widget child) {
    if (!(isDesktop || isWebDesktop)) {
      return GestureDetector(
        onLongPressDown: (e) {
          final x = e.globalPosition.dx;
          final y = e.globalPosition.dy;
          mobileTabContextMenuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onLongPressUp: () {
          mobileShowTabVisibilityMenu();
        },
        child: child,
      );
    } else {
      return Listener(
          onPointerDown: (e) {
            if (e.kind != ui.PointerDeviceKind.mouse) {
              return;
            }
            if (e.buttons == 2) {
              showRightMenu(
                (CancelFunc cancelFunc) {
                  return visibleContextMenu(cancelFunc);
                },
                target: e.position,
              );
            }
          },
          child: child);
    }
  }

  Widget visibleContextMenu(CancelFunc cancelFunc) {
    final model = Provider.of<PeerTabModel>(context);
    final menu = List<MenuEntrySwitchSync>.empty(growable: true);
    for (int i = 0; i < model.orders.length; i++) {
      int tabIndex = model.orders[i];
      if (tabIndex < 0 || tabIndex >= PeerTabModel.maxTabCount) continue;
      if (!model.isEnabled[tabIndex]) continue;
      menu.add(MenuEntrySwitchSync(
          switchType: SwitchType.scheckbox,
          text: model.tabTooltip(tabIndex),
          currentValue: model.isVisibleEnabled[tabIndex],
          setter: (show) async {
            model.setTabVisible(tabIndex, show);
            // Do not hide the current menu (checkbox)
            // cancelFunc();
          },
          enabled: (!isOptVisiableFixed).obs));
    }
    return mod_menu.PopupMenu(
        items: menu
            .map((entry) => entry.build(
                context,
                const MenuConfig(
                  commonColor: MyTheme.accent,
                  height: 20.0,
                  dividerHeight: 12.0,
                )))
            .expand((i) => i)
            .toList());
  }

  Widget createMultiSelectionBar(PeerTabModel model) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Offstage(
          offstage: model.selectedPeers.isEmpty,
          child: Row(
            children: [
              deleteSelection(),
              addSelectionToFav(),
              addSelectionToAb(),
              editSelectionTags(),
            ],
          ),
        ),
        Row(
          children: [
            selectionCount(model.selectedPeers.length),
            selectAll(model),
            closeSelection(),
          ],
        )
      ],
    );
  }

  Widget deleteSelection() {
    final model = Provider.of<PeerTabModel>(context);
    if (model.currentTab == PeerTabIndex.group.index) {
      return Offstage();
    }
    return _hoverAction(
        context: context,
        toolTip: translate('Delete'),
        onTap: () {
          onSubmit() async {
            final peers = model.selectedPeers;
            switch (model.currentTab) {
              case 0:
                for (var p in peers) {
                  await bind.mainRemovePeer(id: p.id);
                }
                bind.mainLoadRecentPeers();
                break;
              case 1:
                final favs = (await bind.mainGetFav()).toList();
                peers.map((p) {
                  favs.remove(p.id);
                }).toList();
                await bind.mainStoreFav(favs: favs);
                bind.mainLoadFavPeers();
                break;
              case 2:
                for (var p in peers) {
                  await bind.mainRemoveDiscovered(id: p.id);
                }
                bind.mainLoadLanPeers();
                break;
              case 3:
                await gFFI.abModel.deletePeers(peers.map((p) => p.id).toList());
                break;
              default:
                break;
            }
            gFFI.peerTabModel.setMultiSelectionMode(false);
            if (model.currentTab != 3) showToast(translate('Successful'));
          }

          deleteConfirmDialog(onSubmit, translate('Delete'));
        },
        child: Icon(Icons.delete, color: Colors.red));
  }

  Widget addSelectionToFav() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage:
          model.currentTab != PeerTabIndex.recent.index, // show based on recent
      child: _hoverAction(
        context: context,
        toolTip: translate('Add to Favorites'),
        onTap: () async {
          final peers = model.selectedPeers;
          final favs = (await bind.mainGetFav()).toList();
          for (var p in peers) {
            if (!favs.contains(p.id)) {
              favs.add(p.id);
            }
          }
          await bind.mainStoreFav(favs: favs);
          model.setMultiSelectionMode(false);
          showToast(translate('Successful'));
        },
        child: Icon(PeerTabModel.icons[PeerTabIndex.fav.index]),
      ).marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget addSelectionToAb() {
    final model = Provider.of<PeerTabModel>(context);
    final addressbooks = gFFI.abModel.addressBooksCanWrite();
    if (model.currentTab == PeerTabIndex.ab.index) {
      addressbooks.remove(gFFI.abModel.currentName.value);
    }
    return Offstage(
      offstage: !gFFI.userModel.isLogin || addressbooks.isEmpty,
      child: _hoverAction(
        context: context,
        toolTip: translate('Add to address book'),
        onTap: () {
          final peers = model.selectedPeers.map((e) => Peer.copy(e)).toList();
          addPeersToAbDialog(peers);
          model.setMultiSelectionMode(false);
        },
        child: Icon(PeerTabModel.icons[PeerTabIndex.ab.index]),
      ).marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget editSelectionTags() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage: !gFFI.userModel.isLogin ||
          model.currentTab != PeerTabIndex.ab.index ||
          gFFI.abModel.currentAbTags.isEmpty,
      child: _hoverAction(
              context: context,
              toolTip: translate('Edit Tag'),
              onTap: () {
                editAbTagDialog(List.empty(), (selectedTags) async {
                  final peers = model.selectedPeers;
                  await gFFI.abModel.changeTagForPeers(
                      peers.map((p) => p.id).toList(), selectedTags);
                  model.setMultiSelectionMode(false);
                  showToast(translate('Successful'));
                });
              },
              child: Icon(Icons.tag))
          .marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget selectionCount(int count) {
    return Align(
      alignment: Alignment.center,
      child: Text('$count ${translate('Selected')}'),
    );
  }

  Widget selectAll(PeerTabModel model) {
    return Offstage(
      offstage:
          model.selectedPeers.length >= model.currentTabCachedPeers.length,
      child: _hoverAction(
        context: context,
        toolTip: translate('Select All'),
        onTap: () {
          model.selectAll();
        },
        child: Icon(Icons.select_all),
      ).marginOnly(left: 6),
    );
  }

  Widget closeSelection() {
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
            context: context,
            toolTip: translate('Close'),
            onTap: () {
              model.setMultiSelectionMode(false);
            },
            child: Icon(Icons.clear))
        .marginOnly(left: 6);
  }

  Widget _toggleTags() {
    return _hoverAction(
        context: context,
        toolTip: translate('Toggle Tags'),
        hoverableWhenfalse: hideAbTagsPanel,
        child: Icon(
          Icons.tag_rounded,
          size: 18,
        ),
        onTap: () async {
          await bind.mainSetLocalOption(
              key: kOptionHideAbTagsPanel,
              value: hideAbTagsPanel.value ? defaultOptionNo : "Y");
          hideAbTagsPanel.value = !hideAbTagsPanel.value;
        });
  }

  List<Widget> _landscapeRightActions(BuildContext context) {
    return [
      const PeerSearchBar().marginOnly(right: 13),
      _createPeerViewTypeSwitch(context),
      const PeerSortSelector().marginOnly(left: 13),
    ];
  }

  List<Widget> _portraitRightActions(BuildContext context) {
    return [
      const PeerSearchBar(),
    ];
  }
}

class PeerSearchBar extends StatefulWidget {
  const PeerSearchBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PeerSearchBarState();
}

class _PeerSearchBarState extends State<PeerSearchBar> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (peerSearchExpanded.value) {
        return _buildExpandedSearchBar();
      } else {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              peerSearchExpanded.value = true;
            },
            child: SvgPicture.asset(
              'assets/icons/main_peer_search.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                  Theme.of(context).hintColor, BlendMode.srcIn),
            ),
          ),
        );
      }
    });
  }

  Widget _buildExpandedSearchBar() {
    final tabTheme = MyTheme.peerTab(context);
    final hintColor = Theme.of(context).hintColor;
    return Row(
      children: [
        SvgPicture.asset(
          'assets/icons/main_peer_search.svg',
          width: 18,
          height: 18,
          colorFilter: ColorFilter.mode(hintColor, BlendMode.srcIn),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            autofocus: true,
            controller: peerSearchTextController,
            onChanged: (searchText) {
              peerSearchText.value = searchText;
            },
            focusNode: _focusNode,
            textAlign: TextAlign.start,
            maxLines: 1,
            cursorColor: Colors.black54,
            cursorHeight: 18,
            cursorWidth: 1,
            style:
                TextStyle(fontSize: isMobile ? 14 : tabTheme.fontSize, color: Colors.black87),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              hintText: translate("Search ID"),
              hintStyle:
                  TextStyle(fontSize: isMobile ? 14 : tabTheme.fontSize, color: hintColor),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              fillColor: Colors.transparent,
              filled: false,
              isDense: true,
            ),
          ).workaroundFreezeLinuxMint(),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              peerSearchTextController.clear();
              peerSearchText.value = "";
              peerSearchExpanded.value = false;
            },
            child: SvgPicture.asset(
              'assets/icons/topbar-close.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(hintColor, BlendMode.srcIn),
            ),
          ),
        ),
      ],
    );
  }
}

class PeerSortSelector extends StatelessWidget {
  const PeerSortSelector({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tabTheme = MyTheme.peerTab(context);
    final iconTheme = MyTheme.sidebarIconButton(context);
    return Obx(() {
      var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (details) {
            final x = details.globalPosition.dx;
            final y = details.globalPosition.dy;
            menuPos = RelativeRect.fromLTRB(x, y, x, y);
          },
          onTap: () {
            showMenu<String>(
              context: context,
              position: menuPos,
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              items: PeerSortType.values.map((sortType) {
                final isSelected = peerSort.value == sortType;
                return PopupMenuItem<String>(
                  value: sortType,
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        translate(sortType),
                        style: TextStyle(
                          color: isSelected
                              ? tabTheme.listSelectedColor
                              : Colors.black87,
                          fontSize: isMobile ? 14 : tabTheme.fontSize,
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check,
                            size: 16, color: tabTheme.listSelectedColor),
                    ],
                  ),
                );
              }).toList(),
            ).then((value) async {
              if (value != null) {
                peerSort.value = value;
                await bind.setLocalFlutterOption(
                  k: kOptionPeerSorting,
                  v: value,
                );
              }
            });
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                translate(peerSort.value),
                style: TextStyle(
                  color: tabTheme.unselectedTextColor,
                  fontSize: isMobile ? 14 : tabTheme.fontSize,
                ),
              ),
              const SizedBox(width: 4),
              SvgPicture.asset(
                'assets/icons/arrow-connect.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                    iconTheme.iconColor, BlendMode.srcIn),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class PeerViewDropdown extends StatelessWidget {
  const PeerViewDropdown({super.key});

  String _getIconPath(PeerUiType type) {
    switch (type) {
      case PeerUiType.grid:
        return 'assets/icons/main_peer_view_big.svg';
      case PeerUiType.tile:
        return 'assets/icons/main_peer_view_small.svg';
      case PeerUiType.list:
        return 'assets/icons/main_peer_view_list.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabTheme = MyTheme.peerTab(context);
    return Obx(() {
      var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (details) {
            final x = details.globalPosition.dx;
            final y = details.globalPosition.dy;
            menuPos = RelativeRect.fromLTRB(x, y, x, y);
          },
          onTap: () {
            showMenu<PeerUiType>(
              context: context,
              position: menuPos,
              elevation: 8,
              constraints: const BoxConstraints(minWidth: 48, maxWidth: 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              items: PeerUiType.values.map((viewType) {
                return PopupMenuItem<PeerUiType>(
                  value: viewType,
                  height: 36,
                  padding: EdgeInsets.zero,
                  child: Center(
                    child: SvgPicture.asset(
                      _getIconPath(viewType),
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(
                          tabTheme.unselectedTextColor, BlendMode.srcIn),
                    ),
                  ),
                );
              }).toList(),
            ).then((value) async {
              if (value != null) {
                peerCardUiType.value = value;
                await bind.setLocalFlutterOption(
                  k: kOptionPeerCardUiType,
                  v: value.index.toString(),
                );
              }
            });
          },
          child: SvgPicture.asset(
            _getIconPath(peerCardUiType.value),
            width: 18,
            height: 18,
            colorFilter:
                ColorFilter.mode(tabTheme.unselectedTextColor, BlendMode.srcIn),
          ),
        ),
      );
    });
  }
}

class PeerSortDropdown extends StatefulWidget {
  const PeerSortDropdown({super.key});

  @override
  State<PeerSortDropdown> createState() => _PeerSortDropdownState();
}

class _PeerSortDropdownState extends State<PeerSortDropdown> {
  _PeerSortDropdownState() {
    if (!PeerSortType.values.contains(peerSort.value)) {
      _loadLocalOptions();
    }
  }

  void _loadLocalOptions() {
    peerSort.value = PeerSortType.remoteHost;
    bind.setLocalFlutterOption(
      k: kOptionPeerSorting,
      v: peerSort.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Theme.of(context).textTheme.titleLarge?.color,
        fontSize: MenuConfig.defaultFontSize,
        fontWeight: FontWeight.normal);
    List<PopupMenuEntry> items = List.empty(growable: true);
    items.add(PopupMenuItem(
        height: 36,
        enabled: false,
        child: Text(translate("Sort by"), style: style)));
    for (var e in PeerSortType.values) {
      items.add(PopupMenuItem(
          height: 36,
          child: Obx(() => Center(
                child: SizedBox(
                  height: 36,
                  child: getRadio(
                      Text(translate(e), style: style), e, peerSort.value,
                      dense: true, (String? v) async {
                    if (v != null) {
                      peerSort.value = v;
                      await bind.setLocalFlutterOption(
                        k: kOptionPeerSorting,
                        v: peerSort.value,
                      );
                    }
                  }),
                ),
              ))));
    }

    var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
    return GestureDetector(
      onTapDown: (details) {
        final x = details.globalPosition.dx;
        final y = details.globalPosition.dy;
        menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onTap: () => showMenu(
        context: context,
        position: menuPos,
        items: items,
        elevation: 8,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          translate('Sort by'),
          style: TextStyle(
            color: Colors.black54,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class RefreshWidget extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final RxBool? spinning;
  const RefreshWidget(
      {super.key, required this.onPressed, required this.child, this.spinning});

  @override
  State<RefreshWidget> createState() => RefreshWidgetState();
}

class RefreshWidgetState extends State<RefreshWidget> {
  double turns = 0.0;
  bool hover = false;

  @override
  void initState() {
    super.initState();
    widget.spinning?.listen((v) {
      if (v && mounted) {
        setState(() {
          turns += 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: Theme.of(context).colorScheme.background,
      borderRadius: BorderRadius.circular(6),
    );
    return AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 200),
        onEnd: () {
          if (widget.spinning?.value == true && mounted) {
            setState(() => turns += 1.0);
          }
        },
        child: Container(
          padding: EdgeInsets.all(4.0),
          margin: EdgeInsets.symmetric(horizontal: 1),
          decoration: hover ? deco : null,
          child: InkWell(
              onTap: () {
                if (mounted) setState(() => turns += 1.0);
                widget.onPressed();
              },
              onHover: (value) {
                if (mounted) {
                  setState(() {
                    hover = value;
                  });
                }
              },
              child: widget.child),
        ));
  }
}

Widget _hoverAction(
    {required BuildContext context,
    required Widget child,
    required Function() onTap,
    required String toolTip,
    GestureTapDownCallback? onTapDown,
    RxBool? hoverableWhenfalse,
    EdgeInsetsGeometry padding = const EdgeInsets.all(4.0)}) {
  final hover = false.obs;
  final deco = BoxDecoration(
    color: Theme.of(context).colorScheme.background,
    borderRadius: BorderRadius.circular(6),
  );
  return Tooltip(
    message: toolTip,
    child: Obx(
      () => Container(
          margin: EdgeInsets.symmetric(horizontal: 1),
          decoration:
              (hover.value || hoverableWhenfalse?.value == false) ? deco : null,
          child: InkWell(
              onHover: (value) => hover.value = value,
              onTap: onTap,
              onTapDown: onTapDown,
              child: Container(padding: padding, child: child))),
    ),
  );
}

class PullDownMenuEntryImpl extends StatelessWidget
    implements PullDownMenuEntry {
  final Widget child;
  const PullDownMenuEntryImpl({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
