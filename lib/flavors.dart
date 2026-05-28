import 'package:flutter/material.dart';

enum Flavor {
  customerA,
  customerB,
  customerC,
}

class F {
  static late final Flavor appFlavor;

  static String get name => appFlavor.name;

  static String get title {
    switch (appFlavor) {
      case Flavor.customerA:
        return 'Customer A Wallet';
      case Flavor.customerB:
        return 'Customer B Wallet';
      case Flavor.customerC:
        return 'Customer C Wallet';
    }
  }

  static Color get primaryColor {
    switch (appFlavor) {
      case Flavor.customerA:
        return const Color(0xFF1E88E5); // 蓝
      case Flavor.customerB:
        return const Color(0xFF7B1FA2); // 紫
      case Flavor.customerC:
        return const Color(0xFF00897B); // 青
    }
  }

  static Color get secondaryColor {
    switch (appFlavor) {
      case Flavor.customerA:
        return const Color(0xFF42A5F5);
      case Flavor.customerB:
        return const Color(0xFF9C27B0);
      case Flavor.customerC:
        return const Color(0xFF26A69A);
    }
  }
}
