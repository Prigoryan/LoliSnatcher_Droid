import 'package:flutter/material.dart';

class ConfirmButton extends StatelessWidget {
  const ConfirmButton({
    this.text = 'Confirm',
    this.action,
    this.returnData = true,
    this.withIcon = false,
    this.customIcon,
    super.key,
  });

  final String text;
  final VoidCallback? action;
  final dynamic returnData;
  final bool withIcon;
  final IconData? customIcon;

  @override
  Widget build(BuildContext context) {
    if (withIcon) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: () {
          if (action != null) {
            action?.call();
          } else {
            Navigator.of(context).pop(returnData);
          }
        },
        icon: Icon(withIcon ? (customIcon ?? Icons.check) : null),
        label: Text(text),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: () {
        if (action != null) {
          action?.call();
        } else {
          Navigator.of(context).pop(returnData);
        }
      },
      child: Text(text),
    );
  }
}
