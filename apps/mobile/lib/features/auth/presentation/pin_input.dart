import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PinInput extends StatefulWidget {
  const PinInput({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.autofocus = false,
  });

  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool autofocus;

  @override
  State<PinInput> createState() => PinInputState();
}

class PinInputState extends State<PinInput> {
  final controller = TextEditingController();

  void clear() {
    controller.clear();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('pin-input'),
      controller: controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: true,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      maxLength: 4,
      style: const TextStyle(
        fontSize: 28,
        letterSpacing: 8,
        fontWeight: FontWeight.w800,
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(counterText: '', hintText: '0000'),
      onChanged: (value) {
        if (value.length == 4) {
          widget.onCompleted(value);
        }
      },
      onSubmitted: (value) {
        if (value.length == 4) {
          widget.onCompleted(value);
        }
      },
    );
  }
}
