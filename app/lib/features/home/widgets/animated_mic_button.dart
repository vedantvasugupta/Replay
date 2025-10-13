import 'dart:math' as math;

import 'package:flutter/material.dart';

enum MicButtonState {
  idle,
  recording,
  uploading,
}

class AnimatedMicButton extends StatefulWidget {
  const AnimatedMicButton({
    required this.state,
    required this.onTap,
    this.size = 180,
    super.key,
  });

  final MicButtonState state;
  final VoidCallback? onTap;
  final double size;

  @override
  State<AnimatedMicButton> createState() => _AnimatedMicButtonState();
}

class _AnimatedMicButtonState extends State<AnimatedMicButton>
    with TickerProviderStateMixin {
  late AnimationController _breatheController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _breatheAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Breathing animation for idle state
    _breatheController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _breatheAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _breatheController,
        curve: Curves.easeInOut,
      ),
    );

    // Pulse animation for recording state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );

    // Rotate animation for uploading state
    _rotateController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _updateAnimations();
  }

  @override
  void didUpdateWidget(AnimatedMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    _breatheController.stop();
    _pulseController.stop();
    _rotateController.stop();

    switch (widget.state) {
      case MicButtonState.idle:
        _breatheController.repeat(reverse: true);
        break;
      case MicButtonState.recording:
        _pulseController.repeat(reverse: true);
        break;
      case MicButtonState.uploading:
        _rotateController.repeat();
        break;
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Color _getButtonColor() {
    switch (widget.state) {
      case MicButtonState.idle:
        return const Color(0xFF6366F1); // Primary accent
      case MicButtonState.recording:
        return const Color(0xFFFF3B30); // Recording red
      case MicButtonState.uploading:
        return const Color(0xFF6366F1);
    }
  }

  IconData _getIcon() {
    switch (widget.state) {
      case MicButtonState.idle:
        return Icons.mic;
      case MicButtonState.recording:
        return Icons.stop_rounded;
      case MicButtonState.uploading:
        return Icons.mic;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _breatheController,
          _pulseController,
          _rotateController,
        ]),
        builder: (context, child) {
          double scale = 1.0;
          if (widget.state == MicButtonState.idle) {
            scale = _breatheAnimation.value;
          } else if (widget.state == MicButtonState.recording) {
            scale = _pulseAnimation.value;
          }

          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ripples for recording state
                if (widget.state == MicButtonState.recording) ...[
                  _buildRipple(1.0, _pulseAnimation.value * 0.3),
                  _buildRipple(0.7, _pulseAnimation.value * 0.5),
                  _buildRipple(0.4, _pulseAnimation.value * 0.7),
                ],

                // Main button
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: _getButtonColor(),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getButtonColor().withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: widget.state == MicButtonState.uploading
                      ? Transform.rotate(
                          angle: _rotateController.value * 2 * math.pi,
                          child: Icon(
                            _getIcon(),
                            size: widget.size * 0.4,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _getIcon(),
                          size: widget.size * 0.4,
                          color: Colors.white,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRipple(double baseOpacity, double scale) {
    return Container(
      width: widget.size * (1 + scale),
      height: widget.size * (1 + scale),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFF3B30).withOpacity(baseOpacity * (1 - scale)),
          width: 2,
        ),
      ),
    );
  }
}
