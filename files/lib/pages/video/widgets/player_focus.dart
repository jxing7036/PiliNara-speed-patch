import 'dart:async';
import 'dart:ffi';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey, HardwareKeyboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 是否是我们把中文输入法关成英文的（失焦时负责还原）
bool _imeRestoreOpen = false;

/// Windows 输入法（IME）辅助：播放器拿到焦点时把中文输入法切成英文，
/// 离开播放器时再还原。
///
/// 否则开着中文输入法按 Z/X/C 会被输入法吞掉（先触发候选词），
/// 必须先手动切中英文才能用快捷键。
class _WindowsIme {
  static bool _inited = false;
  static bool _available = false;
  static late int Function() _getActiveWindow;
  static late int Function(int) _immGetContext;
  static late int Function(int, int) _immSetOpenStatus;
  static late int Function(int) _immGetOpenStatus;
  static late int Function(int, int) _immReleaseContext;

  static bool get _ok {
    if (!_inited) {
      _inited = true;
      if (Platform.isWindows) {
        try {
          final user32 = DynamicLibrary.open('user32.dll');
          final imm32 = DynamicLibrary.open('imm32.dll');
          _getActiveWindow = user32.lookupFunction<IntPtr Function(),
              int Function()>('GetActiveWindow');
          _immGetContext = imm32.lookupFunction<IntPtr Function(IntPtr),
              int Function(int)>('ImmGetContext');
          _immSetOpenStatus = imm32.lookupFunction<
              Int32 Function(IntPtr, Int32),
              int Function(int, int)>('ImmSetOpenStatus');
          _immGetOpenStatus = imm32.lookupFunction<Int32 Function(IntPtr),
              int Function(int)>('ImmGetOpenStatus');
          _immReleaseContext = imm32.lookupFunction<
              Int32 Function(IntPtr, IntPtr),
              int Function(int, int)>('ImmReleaseContext');
          _available = true;
        } catch (_) {
          _available = false;
        }
      }
    }
    return _available;
  }

  /// 当前输入法是否处于「中文（打开）」状态；未知返回 null
  static bool? isOpen() {
    if (!_ok) return null;
    final hwnd = _getActiveWindow();
    if (hwnd == 0) return null;
    final himc = _immGetContext(hwnd);
    if (himc == 0) return null;
    try {
      return _immGetOpenStatus(himc) != 0;
    } finally {
      _immReleaseContext(hwnd, himc);
    }
  }

  /// 切换输入法中/英文状态（false = 英文）
  static void setOpen(bool open) {
    if (!_ok) return;
    final hwnd = _getActiveWindow();
    if (hwnd == 0) return;
    final himc = _immGetContext(hwnd);
    if (himc == 0) return;
    try {
      _immSetOpenStatus(himc, open ? 1 : 0);
    } finally {
      _immReleaseContext(hwnd, himc);
    }
  }
}

class PlayerFocus extends StatelessWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    this.introController,
    required this.onSendDanmaku,
    this.canPlay,
    this.onSkipSegment,
    this.onRefresh,
    this.focusNode,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final CommonIntroController? introController;
  final VoidCallback onSendDanmaku;
  final ValueGetter<bool>? canPlay;
  final ValueGetter<bool>? onSkipSegment;
  final VoidCallback? onRefresh;

  /// 外部持有的焦点节点：供页面在点击/悬停视频区时抢回焦点（恢复方向键音量控制）
  final FocusNode? focusNode;

  static bool _shouldHandle(LogicalKeyboardKey logicalKey) {
    return logicalKey == LogicalKeyboardKey.tab ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onFocusChange: (hasFocus) {
        // 聚焦播放器：把中文输入法切英文（否则 Z/X/C 会被输入法吞掉）
        // 离开播放器：还原原来的中英文状态，保证输入框还能打中文
        if (hasFocus) {
          _keepImeOff();
        } else {
          _restoreIme();
        }
      },
      onKeyEvent: (node, event) {
        final handled = _handleKey(context, event);
        if (handled || _shouldHandle(event.logicalKey)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        // 播放中用户可能又手动切回中文，点一下播放器就再切回英文
        onPointerDown: (_) => _keepImeOff(),
        child: child,
      ),
    );
  }

  /// 把输入法切到英文；只在当前是中文时记一次，供失焦还原
  void _keepImeOff() {
    if (_imeRestoreOpen) return;
    if (_WindowsIme.isOpen() == true) {
      _imeRestoreOpen = true;
      _WindowsIme.setOpen(false);
    }
  }

  /// 还原进入播放器前的中文输入法状态
  void _restoreIme() {
    if (!_imeRestoreOpen) return;
    _imeRestoreOpen = false;
    _WindowsIme.setOpen(true);
  }

  bool get isFullScreen => plPlayerController.isFullScreen.value;
  bool get hasPlayer => plPlayerController.videoPlayerController != null;

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? math.min(
            plPlayerController.maxVolume,
            plPlayerController.volume.value + 0.1,
          )
        : math.max(0.0, plPlayerController.volume.value - 0.1);
    plPlayerController.setVolume(volume);
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      plPlayerController.cancelLongPressTimer();
    }
  }


  /// 单次倍速步进（0.1x），使用整数十份位运算避免浮点精度累积误差
  void _changeSpeed({required bool isIncrease}) {
    final tenths = (plPlayerController.playbackSpeed * 10).round();
    final newTenths = isIncrease
        ? (tenths + 1).clamp(1, 60)
        : (tenths - 1).clamp(1, 60);
    final newSpeed = newTenths / 10.0;
    plPlayerController
      ..setManualPlaybackSpeed(newSpeed)
      ..showKeyboardSpeedToast(newSpeed);
  }

  /// X/C 长按：按下步进一次，300ms 延迟后持续步进（每 100ms），松开取消
  void _updateSpeed(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _changeSpeed(isIncrease: isIncrease);
        plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer(
            const Duration(milliseconds: 300),
            () => plPlayerController
              ..cancelLongPressTimer()
              ..longPressTimer = Timer.periodic(
                const Duration(milliseconds: 100),
                (_) => _changeSpeed(isIncrease: isIncrease),
              ),
          );
      }
    } else if (event is KeyUpEvent) {
      plPlayerController.cancelLongPressTimer();
    }
  }

  bool _handleKey(BuildContext context, KeyEvent event) {
    final key = event.logicalKey;

    final isKeyQ = key == LogicalKeyboardKey.keyQ;
    if (isKeyQ || key == LogicalKeyboardKey.keyR) {
      if (HardwareKeyboard.instance.isMetaPressed) {
        if (isKeyQ && Platform.isMacOS) {
          exit(0);
        }
        return true;
      }
      if (event is KeyDownEvent) {
        if (plPlayerController.isLive) {
          onRefresh?.call();
        } else {
          introController!.onStartTriple();
        }
      } else if (event is KeyUpEvent && !plPlayerController.isLive) {
        introController!.onCancelTriple(isKeyQ);
      }
      return true;
    } else if (event is KeyDownEvent) {
      if (introController?.isTripling ?? false) {
        introController!.onCancelTriple();
      }
    }

    final isArrowUp = key == LogicalKeyboardKey.arrowUp;
    if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
      _updateVolume(event, isIncrease: isArrowUp);
      return true;
    }


    // Z：在 1.0x 与「上次倍速」之间来回切换（同时取消 X/C 长按定时器，防止后续 tick 改回去）
    if (key == LogicalKeyboardKey.keyZ) {
      if (event is KeyDownEvent && !plPlayerController.isLive && hasPlayer) {
        plPlayerController.cancelLongPressTimer();
        unawaited(plPlayerController.toggleNormalSpeed());
      }
      return true;
    }

    // X/C 倍速加减（X 减速、C 加速），支持长按持续调节（每 100ms 步进 0.1x）
    if (key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.keyC) {
      if (!plPlayerController.isLive && hasPlayer) {
        _updateSpeed(event, isIncrease: key == LogicalKeyboardKey.keyC);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!plPlayerController.isLive) {
        if (event is KeyDownEvent) {
          if (hasPlayer && !plPlayerController.longPressStatus.value) {
            plPlayerController
              ..longPressTimer?.cancel()
              ..longPressTimer = Timer(
                const Duration(milliseconds: 200),
                () => plPlayerController
                  ..cancelLongPressTimer()
                  ..setLongPressStatus(true),
              );
          }
        } else if (event is KeyUpEvent) {
          plPlayerController.cancelLongPressTimer();
          if (hasPlayer) {
            if (plPlayerController.longPressStatus.value) {
              plPlayerController.setLongPressStatus(false);
            } else {
              plPlayerController.onForward(
                plPlayerController.fastForBackwardDuration,
              );
            }
          }
        }
      }
      return true;
    }

    if (event is KeyDownEvent) {
      switch (key) {
        case LogicalKeyboardKey.space:
          if (plPlayerController.isLive || canPlay!()) {
            if (hasPlayer) {
              plPlayerController.onDoubleTapCenter();
            }
          }
          return true;

        case LogicalKeyboardKey.keyF:
          final isFullScreen = this.isFullScreen;
          if (isFullScreen && plPlayerController.controlsLock.value) {
            plPlayerController
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          plPlayerController.triggerFullScreen(
            status: !isFullScreen,
            inAppFullScreen: HardwareKeyboard.instance.isShiftPressed,
          );
          return true;

        case LogicalKeyboardKey.keyD:
          final newVal = !plPlayerController.enableShowDanmakuAdaptive.value;
          plPlayerController.enableShowDanmakuAdaptive.value = newVal;
          if (!plPlayerController.tempPlayerConf) {
            GStorage.setting.put(
              plPlayerController.isLive
                  ? SettingBoxKey.enableShowLiveDanmaku
                  : SettingBoxKey.enableShowDanmaku,
              newVal,
            );
          }
          return true;

        case LogicalKeyboardKey.keyP:
          if (PlatformUtils.isDesktop && hasPlayer && !isFullScreen) {
            plPlayerController
              ..toggleDesktopPip()
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          return true;

        case LogicalKeyboardKey.keyM:
          if (hasPlayer) {
            final isMuted = !plPlayerController.isMuted;
            plPlayerController.videoPlayerController!.setVolume(
              isMuted ? 0 : plPlayerController.volume.value * 100,
            );
            plPlayerController.isMuted = isMuted;
            SmartDialog.showToast('${isMuted ? '' : '取消'}静音');
          }
          return true;

        case LogicalKeyboardKey.keyS:
          if (hasPlayer && isFullScreen) {
            plPlayerController.takeScreenshot();
          }
          return true;

        case LogicalKeyboardKey.keyL:
          if (isFullScreen || plPlayerController.isDesktopPip) {
            plPlayerController.onLockControl(
              !plPlayerController.controlsLock.value,
            );
          }
          return true;

        case LogicalKeyboardKey.enter:
          if (onSkipSegment?.call() ?? false) {
            return true;
          }
          onSendDanmaku();
          return true;
      }

      if (!plPlayerController.isLive) {
        final isDigit1 = key == LogicalKeyboardKey.digit1;
        if (isDigit1 || key == LogicalKeyboardKey.digit2) {
          if (HardwareKeyboard.instance.isShiftPressed && hasPlayer) {
            final speed = isDigit1 ? 1.0 : 2.0;
            // 无条件走手动调速：锁定态下即使速度相同也需要解除锁定
            plPlayerController.setManualPlaybackSpeed(speed);
            SmartDialog.showToast('${speed}x播放');
          }
          return true;
        }

        switch (key) {
          case LogicalKeyboardKey.arrowLeft:
            if (hasPlayer) {
              plPlayerController.onBackward(
                plPlayerController.fastForBackwardDuration,
              );
            }
            return true;

          case LogicalKeyboardKey.keyW:
            if (HardwareKeyboard.instance.isMetaPressed) {
              return true;
            }
            introController?.actionCoinVideo();
            return true;

          case LogicalKeyboardKey.keyE:
            introController?.actionFavVideo(isQuick: true);
            return true;

          case LogicalKeyboardKey.keyT || LogicalKeyboardKey.keyV:
            introController?.viewLater();
            return true;

          case LogicalKeyboardKey.keyG:
            if (introController case final UgcIntroController ugcCtr) {
              ugcCtr.actionRelationMod(context);
            }
            return true;

          case LogicalKeyboardKey.bracketLeft:
            if (introController case final introController?) {
              if (!introController.prevPlay(manual: true)) {
                SmartDialog.showToast('已经是第一集了');
              }
            }
            return true;

          case LogicalKeyboardKey.bracketRight:
            if (introController case final introController?) {
              if (!introController.nextPlay(manual: true)) {
                SmartDialog.showToast('已经是最后一集了');
              }
            }
            return true;
        }
      }
    }

    return false;
  }
}
