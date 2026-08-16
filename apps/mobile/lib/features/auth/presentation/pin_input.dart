import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PinInput extends StatefulWidget {
  const PinInput({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.autofocus = false,
    this.label = 'PIN',
  });

  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool autofocus;
  final String label;

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
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: widget.label, counterText: ''),
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
