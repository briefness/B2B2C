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
}
