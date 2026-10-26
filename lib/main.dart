import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const CultivaStockApp());
}

// ============================================================================
// CONSTANTES E CATEGORIAS DO SISTEMA
// ============================================================================

const List<String> kProductCategories = [
  'Sementes',
  'Defensivos',
  'Fertilizantes',
  'Combustíveis',
  'Biológicos',
  'Corretivos',
  'Peças & Equipamentos',
];

const List<String> kProductUnits = [
  'Sacos',
  'Litros',
  'Kg',
  'Doses',
  'Unidades',
  'Galões',
  'Caixas',
  'Toneladas',
];

const List<String> kConsumptionPeriods = [
  'Por Mês',
  'Por Semana',
  'Por Dia',
];

// ============================================================================
// FORMATADORES E HELPERS (Sem dependências externas)
// ============================================================================

class CultivaFormat {
  static String currency(double value) {
    final isNegative = value < 0;
    final absVal = value.abs();
    final fixed = absVal.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    final buffer = StringBuffer();
    int count = 0;
    for (int i = intPart.length - 1; i >= 0; i--) {
      buffer.write(intPart[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write('.');
      }
    }
    final formattedInt = buffer.toString().split('').reversed.join('');
    final sign = isNegative ? '-' : '';
    return '${sign}R\$ $formattedInt,$decPart';
  }

  static String number(num value) {
    if (value is double && value != value.roundToDouble()) {
      return value.toStringAsFixed(1).replaceAll('.', ',');
    }
    final intPart = value.toInt().toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = intPart.length - 1; i >= 0; i--) {
      buffer.write(intPart[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write('.');
      }
    }
    return buffer.toString().split('').reversed.join('');
  }

  static String dateOnly(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }

  static String dateTimeShort(DateTime d) {
    const months = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez'
    ];
    final day = d.day.toString().padLeft(2, '0');
    final month = months[d.month - 1];
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day $month • $hour:$min';
  }
}

// ============================================================================
// DOMÍNIO, MODELOS DE DADOS E REGRAS DE NEGÓCIO AGRO
// ============================================================================

enum MovementType { entrada, saida, ajuste }

enum StockAlertLevel { normal, atencao, critico, excesso, vencimentoProximo }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final StockAlertLevel priority;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.priority,
    this.isRead = false,
  });

  // Cor de fundo que preenche todo o container da notificação conforme a prioridade
  Color get backgroundColor {
    switch (priority) {
      case StockAlertLevel.critico:
        return const Color(0xFFFFEBEE); // Vermelho suave
      case StockAlertLevel.atencao:
      case StockAlertLevel.vencimentoProximo:
        return const Color(0xFFFFF3E0); // Laranja suave
      case StockAlertLevel.excesso:
        return const Color(0xFFE1F5FE); // Azul suave
      case StockAlertLevel.normal:
        return const Color(0xFFE8F5E9); // Verde suave
    }
  }

  Color get borderColor {
    switch (priority) {
      case StockAlertLevel.critico:
        return const Color(0xFFEF9A9A);
      case StockAlertLevel.atencao:
      case StockAlertLevel.vencimentoProximo:
        return const Color(0xFFFFCC80);
      case StockAlertLevel.excesso:
        return const Color(0xFF90CAF9);
      case StockAlertLevel.normal:
        return const Color(0xFFA5D6A7);
    }
  }

  Color get textColor {
    switch (priority) {
      case StockAlertLevel.critico:
        return const Color(0xFFC62828);
      case StockAlertLevel.atencao:
      case StockAlertLevel.vencimentoProximo:
        return const Color(0xFFE65100);
      case StockAlertLevel.excesso:
        return const Color(0xFF0277BD);
      case StockAlertLevel.normal:
        return const Color(0xFF1E5631);
    }
  }
}

class StockMovement {
  final String id;
  final DateTime date;
  final double quantity;
  final MovementType type;
  final String destination;
  final String responsible;
  final String description;
  final String? invoiceNumber;

  StockMovement({
    required this.id,
    required this.date,
    required this.quantity,
    required this.type,
    required this.destination,
    required this.responsible,
    required this.description,
    this.invoiceNumber,
  });
}

class Product {
  final String id;
  final String name;
  final String description;
  final String category;
  double currentBalance;
  final String unit;
  final double minimumStockDays;
  final DateTime? validity;
  final String? lot;
  final String? supplier;
  final double acquisitionPrice;
  final List<StockMovement> history;
  final double? unusualUsagePercent;
  final String consumptionPeriod; // 'Por Mês', 'Por Semana', 'Por Dia'

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.currentBalance,
    required this.unit,
    required this.minimumStockDays,
    this.validity,
    this.lot,
    this.supplier,
    required this.acquisitionPrice,
    required this.history,
    this.unusualUsagePercent,
    this.consumptionPeriod = 'Por Mês',
  });

  // Lógica de Negócio: Cálculo de Consumo Médio Dinâmico e Reativo
  // Atualiza instantaneamente a cada saída/baixa registrada
  double get averageWeeklyConsumption {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final recentOutflows = history.where(
        (m) => m.type == MovementType.saida && m.date.isAfter(thirtyDaysAgo)).toList();

    if (recentOutflows.isEmpty) return 0.0;

    final totalOutflow = recentOutflows.fold(0.0, (sum, m) => sum + m.quantity);

    // Identifica o período real decorrido desde o primeiro registro de saída
    final earliestDate = recentOutflows.map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final daysElapsed = max(1, DateTime.now().difference(earliestDate).inDays + 1);

    if (daysElapsed <= 7) {
      // Movimentações recentes dentro da mesma semana: reflete o consumo acumulado diretamente
      return totalOutflow;
    } else {
      // Períodos maiores que 7 dias: calcula a taxa média móvel semanal proporcional aos dias observados
      final effectiveDays = min(30, daysElapsed);
      return (totalOutflow / effectiveDays) * 7.0;
    }
  }

  double get averageDailyConsumption => averageWeeklyConsumption / 7.0;

  // Consumo calculado de acordo com a medida escolhida pelo usuário (Por Mês, Por Semana, Por Dia)
  double get averageConsumption {
    switch (consumptionPeriod) {
      case 'Por Dia':
        return averageDailyConsumption;
      case 'Por Mês':
        return averageDailyConsumption * 30.0;
      case 'Por Semana':
      default:
        return averageWeeklyConsumption;
    }
  }

  String get consumptionPeriodLabel {
    switch (consumptionPeriod) {
      case 'Por Dia':
        return '/dia';
      case 'Por Mês':
        return '/mês';
      case 'Por Semana':
      default:
        return '/sem';
    }
  }

  String get consumptionPeriodDescription {
    switch (consumptionPeriod) {
      case 'Por Dia':
        return 'consumo diário';
      case 'Por Mês':
        return 'consumo mensal';
      case 'Por Semana':
      default:
        return 'consumo semanal';
    }
  }

  // Projeção dinâmica de dias restantes de estoque
  int get estimatedDaysRemaining {
    final daily = averageDailyConsumption;
    if (daily <= 0) return 999;
    final days = (currentBalance / daily).floor();
    return max(0, days);
  }

  int? get daysUntilExpiry {
    if (validity == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final valDate = DateTime(validity!.year, validity!.month, validity!.day);
    return valDate.difference(today).inDays;
  }

  // Risco de vencimento: mínimo de 30 dias (ou já vencido)
  bool get hasExpiryRisk {
    if (daysUntilExpiry == null) return false;
    if (daysUntilExpiry! <= 30) return true;
    if (averageDailyConsumption <= 0) return false;
    // Risco de validade se o estoque projetado ultrapassar a validade
    return daysUntilExpiry! <= 60 && estimatedDaysRemaining > daysUntilExpiry!;
  }

  double get unitsAtRiskOfExpiry {
    if (!hasExpiryRisk || daysUntilExpiry == null || daysUntilExpiry! <= 0) return 0;
    final consumableBeforeExpiry = averageDailyConsumption * daysUntilExpiry!;
    final atRisk = currentBalance - consumableBeforeExpiry;
    return atRisk > 0 ? atRisk : 0;
  }

  // Avaliação pura do nível de estoque (Saldo e Consumo)
  StockAlertLevel get stockLevelAlert {
    // 1. Estoque zerado ou negativo: situação sempre Crítica
    if (currentBalance <= 0) {
      return StockAlertLevel.critico;
    }

    // 2. Quando há consumo apurado (saídas registradas)
    if (averageDailyConsumption > 0) {
      final daysLeft = estimatedDaysRemaining;
      if (daysLeft <= minimumStockDays) {
        return StockAlertLevel.critico;
      }
      if (daysLeft <= minimumStockDays + 7 ||
          (unusualUsagePercent != null && unusualUsagePercent! > 20)) {
        return StockAlertLevel.atencao;
      }
      if (daysLeft > 120 && totalInvestedCapital > 30000) {
        return StockAlertLevel.excesso;
      }
      return StockAlertLevel.normal;
    }

    // 3. Sem saídas registradas (consumo zero): avalia o saldo em relação à meta mínima
    if (currentBalance < (minimumStockDays / 2)) {
      return StockAlertLevel.critico;
    }
    if (currentBalance < minimumStockDays) {
      return StockAlertLevel.atencao;
    }

    return StockAlertLevel.normal;
  }

  // Nível de alerta geral: O estoque crítico NUNCA é negligenciado por risco de vencimento
  StockAlertLevel get alertLevel {
    // 1. Se o estoque está crítico, a gravidade crítica tem precedência máxima
    if (stockLevelAlert == StockAlertLevel.critico) {
      return StockAlertLevel.critico;
    }

    // 2. Risco de vencimento (≤ 30 dias)
    if (hasExpiryRisk) {
      return StockAlertLevel.vencimentoProximo;
    }

    // 3. Nível de atenção de estoque
    if (stockLevelAlert == StockAlertLevel.atencao) {
      return StockAlertLevel.atencao;
    }

    // 4. Excesso de estoque
    if (stockLevelAlert == StockAlertLevel.excesso) {
      return StockAlertLevel.excesso;
    }

    return StockAlertLevel.normal;
  }

  String get stockStatusLabel {
    if (stockLevelAlert == StockAlertLevel.critico && hasExpiryRisk) {
      return 'Crítico • Venc.';
    }
    if (stockLevelAlert == StockAlertLevel.atencao && hasExpiryRisk) {
      return 'Atenção • Venc.';
    }
    switch (alertLevel) {
      case StockAlertLevel.critico:
        return 'Crítico';
      case StockAlertLevel.atencao:
        return 'Atenção';
      case StockAlertLevel.vencimentoProximo:
        return 'Risco Venc.';
      case StockAlertLevel.excesso:
        return 'Excesso';
      case StockAlertLevel.normal:
        return 'Normal';
    }
  }

  Color get statusColor {
    switch (alertLevel) {
      case StockAlertLevel.critico:
        return const Color(0xFFC62828);
      case StockAlertLevel.atencao:
      case StockAlertLevel.vencimentoProximo:
        return const Color(0xFFE65100);
      case StockAlertLevel.excesso:
        return const Color(0xFF0277BD);
      case StockAlertLevel.normal:
        return const Color(0xFF1E5631);
    }
  }

  Color get statusBackgroundColor {
    switch (alertLevel) {
      case StockAlertLevel.critico:
        return const Color(0xFFFFEBEE);
      case StockAlertLevel.atencao:
      case StockAlertLevel.vencimentoProximo:
        return const Color(0xFFFFF3E0);
      case StockAlertLevel.excesso:
        return const Color(0xFFE1F5FE);
      case StockAlertLevel.normal:
        return const Color(0xFFE8F3EB);
    }
  }

  double get totalInvestedCapital => currentBalance * acquisitionPrice;

  String get financialHealthLabel {
    if (estimatedDaysRemaining > 120 && averageDailyConsumption > 0) {
      return 'Capital Imobilizado';
    }
    if (alertLevel == StockAlertLevel.critico) {
      return 'Risco Operacional';
    }
    return 'Giro Saudável';
  }

  String get analyticalRecommendation {
    final supplierName = (supplier != null &&
            supplier!.trim().isNotEmpty &&
            supplier != 'Fornecedor Direto' &&
            supplier != 'Fornecedor da NF-e')
        ? ' com o fornecedor $supplier'
        : '';
    final lotName = (lot != null && lot!.trim().isNotEmpty && lot != 'S/L')
        ? 'o lote $lot'
        : 'este lote';

    String stockMsg = '';
    if (stockLevelAlert == StockAlertLevel.critico) {
      if (averageDailyConsumption > 0) {
        stockMsg = 'Estoque crítico: mantendo o consumo recente de ${averageConsumption.toStringAsFixed(1)} ${unit.toLowerCase()}$consumptionPeriodLabel ($consumptionPeriodDescription), o saldo atual poderá durar aproximadamente $estimatedDaysRemaining dias. Reposição recomendada$supplierName.';
      } else {
        stockMsg = 'Estoque crítico: saldo atual de ${CultivaFormat.number(currentBalance)} $unit abaixo da meta mínima de ${minimumStockDays.toInt()} dias. Reposição recomendada$supplierName.';
      }
    } else if (stockLevelAlert == StockAlertLevel.atencao) {
      if (averageDailyConsumption > 0) {
        stockMsg = 'Estoque em atenção: cobertura estimada para $estimatedDaysRemaining dias no ritmo atual. Monitore as próximas saídas de campo.';
      } else {
        stockMsg = 'Estoque em atenção: saldo atual de ${CultivaFormat.number(currentBalance)} $unit está próximo da meta de segurança (${minimumStockDays.toInt()} dias).';
      }
    }

    String expiryMsg = '';
    if (hasExpiryRisk && daysUntilExpiry != null) {
      if (daysUntilExpiry! < 0) {
        expiryMsg = 'Produto vencido: $lotName venceu há ${daysUntilExpiry!.abs()} dias (${CultivaFormat.dateOnly(validity!)}). Não utilize sem liberação agronômica.';
      } else if (daysUntilExpiry! == 0) {
        expiryMsg = 'Atenção ao prazo: $lotName vence hoje (${CultivaFormat.dateOnly(validity!)})! Priorize o consumo imediato no talhão.';
      } else if (daysUntilExpiry! <= 30) {
        expiryMsg = 'Alerta de validade: $lotName vencerá em $daysUntilExpiry dias (${CultivaFormat.dateOnly(validity!)}), dentro do prazo de alerta de 30 dias. Risco de perda.';
      } else {
        expiryMsg = 'Atenção ao prazo: $lotName vencerá em $daysUntilExpiry dias. No ritmo atual, restarão cerca de ${unitsAtRiskOfExpiry.toStringAsFixed(0)} $unit sem utilização.';
      }
    }

    // Se possui ambos os alertas, emite ambas as recomendações sem negligenciar nenhuma
    if (stockMsg.isNotEmpty && expiryMsg.isNotEmpty) {
      return '$stockMsg\n\nALERTA CONJUNTO: $expiryMsg';
    }
    if (stockMsg.isNotEmpty) return stockMsg;
    if (expiryMsg.isNotEmpty) return expiryMsg;
    if (unusualUsagePercent != null && unusualUsagePercent! > 0) {
      return 'Consumo acima da média (+${unusualUsagePercent!.toStringAsFixed(0)}%): verifique intensidade de campo ou eventuais perdas no armazém.';
    }
    if (averageDailyConsumption <= 0) {
      return 'Saldo regular de ${CultivaFormat.number(currentBalance)} $unit. Sem movimentações de saída recentes nos últimos 30 dias para este produto.';
    }
    return 'Saldo estimado para $estimatedDaysRemaining dias considerando o consumo recente de saídas.';
  }
}

// ============================================================================
// REPOSITÓRIO E GERENCIAMENTO DE ESTADO REATIVO (ChangeNotifier)
// ============================================================================

class CultivaStockRepository extends ChangeNotifier {
  static final CultivaStockRepository _instance = CultivaStockRepository._internal();
  factory CultivaStockRepository() => _instance;

  // Gerenciamento e Navegação entre Safras (Editável e por ano)
  final List<String> _safras = ['Safra 2026'];
  String _currentSafra = 'Safra 2026';

  // Armazena estoques e notificações isolados por safra
  final Map<String, List<Product>> _safraProducts = {'Safra 2026': []};
  final Map<String, List<AppNotification>> _safraNotifications = {'Safra 2026': []};

  CultivaStockRepository._internal();

  List<String> get safras => List.unmodifiable(_safras);
  String get currentSafra => _currentSafra;

  List<Product> get _products => _safraProducts.putIfAbsent(_currentSafra, () => []);
  List<AppNotification> get _notifications => _safraNotifications.putIfAbsent(_currentSafra, () => []);

  List<Product> get products => List.unmodifiable(_products);
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int getProductCountForSafra(String safra) => (_safraProducts[safra] ?? []).length;

  void selectSafra(String safraName) {
    if (_safras.contains(safraName)) {
      _currentSafra = safraName;
      _safraProducts.putIfAbsent(_currentSafra, () => []);
      _safraNotifications.putIfAbsent(_currentSafra, () => []);
      notifyListeners();
    }
  }

  void editCurrentSafra(String newSafraName) {
    renameSafra(_currentSafra, newSafraName);
  }

  void renameSafra(String oldSafraName, String newSafraName) {
    final trimmed = newSafraName.trim();
    if (trimmed.isEmpty || trimmed == oldSafraName) return;
    final index = _safras.indexOf(oldSafraName);
    if (index != -1) {
      _safras[index] = trimmed;
    } else {
      _safras.add(trimmed);
    }
    final prods = _safraProducts.remove(oldSafraName) ?? [];
    final notifs = _safraNotifications.remove(oldSafraName) ?? [];
    _safraProducts[trimmed] = prods;
    _safraNotifications[trimmed] = notifs;
    if (_currentSafra == oldSafraName) {
      _currentSafra = trimmed;
    }
    notifyListeners();
  }

  void createNewSafra(String safraName) {
    final trimmed = safraName.trim();
    if (trimmed.isEmpty) return;
    if (!_safras.contains(trimmed)) {
      _safras.add(trimmed);
    }
    _currentSafra = trimmed;
    _safraProducts.putIfAbsent(_currentSafra, () => []);
    _safraNotifications.putIfAbsent(_currentSafra, () => []);

    addNotification(
      title: 'Safra Ativada: $_currentSafra',
      message: 'Nova safra iniciada. O armazém da safra anterior permanece salvo e acessível a qualquer momento.',
      priority: StockAlertLevel.normal,
    );
    notifyListeners();
  }

  bool get hasUnreadNotifications => _notifications.any((n) => !n.isRead);

  void markNotificationsAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void addNotification({
    required String title,
    required String message,
    required StockAlertLevel priority,
  }) {
    _notifications.insert(
      0,
      AppNotification(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        message: message,
        timestamp: DateTime.now(),
        priority: priority,
        isRead: false,
      ),
    );
    notifyListeners();
  }

  int get totalStockUnits {
    return _products.fold<int>(0, (sum, p) => sum + p.currentBalance.toInt());
  }

  int get totalProductsCount => _products.length;

  int get activeCulturesCount {
    return _products.map((p) => p.category).toSet().length;
  }

  List<Product> get criticalAndAttentionProducts {
    return _products.where((p) =>
        p.stockLevelAlert == StockAlertLevel.critico ||
        p.stockLevelAlert == StockAlertLevel.atencao ||
        p.hasExpiryRisk).toList();
  }

  // Cálculo de consumo médio dinâmico filtrado por categoria
  double calculateWeeklyConsumptionForCategory(String category) {
    List<Product> filtered;
    if (category == 'Todas') {
      filtered = _products;
    } else {
      filtered = _products
          .where((p) => p.category.toLowerCase() == category.toLowerCase())
          .toList();
    }
    return filtered.fold(0.0, (sum, p) => sum + p.averageWeeklyConsumption);
  }

  // Adicionar Novo Produto Manualmente
  void addProduct(Product product) {
    _products.add(product);

    addNotification(
      title: 'Produto Cadastrado',
      message: '${product.name} (${product.category}) foi adicionado com saldo inicial de ${product.currentBalance.toInt()} ${product.unit}.',
      priority: StockAlertLevel.normal,
    );

    // 1. Alerta de Estoque Crítico ou Atenção - NUNCA negligenciado
    if (product.stockLevelAlert == StockAlertLevel.critico) {
      addNotification(
        title: 'Estoque Crítico: ${product.name}',
        message: 'Saldo inicial de ${CultivaFormat.number(product.currentBalance)} ${product.unit} está abaixo da meta mínima de ${product.minimumStockDays.toInt()} dias. Reposição recomendada.',
        priority: StockAlertLevel.critico,
      );
    } else if (product.stockLevelAlert == StockAlertLevel.atencao) {
      addNotification(
        title: 'Atenção ao Estoque: ${product.name}',
        message: 'Saldo inicial de ${CultivaFormat.number(product.currentBalance)} ${product.unit} está próximo da meta de segurança (${product.minimumStockDays.toInt()} dias).',
        priority: StockAlertLevel.atencao,
      );
    }

    // 2. Alerta de Vencimento Próximo (mínimo de 30 dias: <= 30 dias) - NUNCA negligenciado
    if (product.validity != null) {
      final days = product.daysUntilExpiry ?? 999;
      if (days <= 30) {
        final String alertTitle;
        final String alertMsg;
        if (days < 0) {
          alertTitle = 'Alerta: Produto Vencido (${product.name})';
          alertMsg = 'O produto ${product.name} já venceu em ${CultivaFormat.dateOnly(product.validity!)} (há ${days.abs()} dias). Verifique o lote ${product.lot ?? 'S/L'}.';
        } else if (days == 0) {
          alertTitle = 'Alerta: Vencimento Hoje (${product.name})';
          alertMsg = 'O produto ${product.name} vence hoje (${CultivaFormat.dateOnly(product.validity!)}). Priorize consumo imediato no campo.';
        } else {
          alertTitle = 'Alerta de Vencimento Próximo: ${product.name}';
          alertMsg = 'Atenção: ${product.name} vence em $days dias (${CultivaFormat.dateOnly(product.validity!)}), dentro do prazo de alerta de 30 dias.';
        }
        addNotification(
          title: alertTitle,
          message: alertMsg,
          priority: StockAlertLevel.vencimentoProximo,
        );
      }
    }

    notifyListeners();
  }

  // Registro de Saída / Baixa do Estoque (Recalcula consumo e alertas dinamicamente)
  void recordOutflow({
    required String productId,
    required double quantity,
    required String destination,
    required String responsible,
    required String description,
  }) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final product = _products[index];
      product.currentBalance = max(0, product.currentBalance - quantity);
      product.history.insert(
        0,
        StockMovement(
          id: 'mov_${DateTime.now().millisecondsSinceEpoch}',
          date: DateTime.now(),
          quantity: quantity,
          type: MovementType.saida,
          destination: destination,
          responsible: responsible,
          description: description,
        ),
      );

      // Notifica se entrou em nível crítico ou atenção
      if (product.alertLevel == StockAlertLevel.critico) {
        addNotification(
          title: 'Estoque Crítico: ${product.name}',
          message: 'Saldo restante de apenas ${product.currentBalance.toInt()} ${product.unit}. Reposição urgente recomendada.',
          priority: StockAlertLevel.critico,
        );
      } else if (product.alertLevel == StockAlertLevel.atencao) {
        addNotification(
          title: 'Atenção ao Estoque: ${product.name}',
          message: 'Saldo estimado para ${product.estimatedDaysRemaining} dias no ritmo recente de saídas.',
          priority: StockAlertLevel.atencao,
        );
      }

      notifyListeners();
    }
  }

  // Registro de Entrada no Estoque (recalcula status e níveis de alerta imediatamente)
  void recordInflow({
    required String productId,
    required double quantity,
    String? supplier,
    String? lot,
    required String responsible,
    String? invoiceNumber,
    String? description,
  }) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final product = _products[index];
      product.currentBalance += quantity;
      product.history.insert(
        0,
        StockMovement(
          id: 'mov_${DateTime.now().millisecondsSinceEpoch}',
          date: DateTime.now(),
          quantity: quantity,
          type: MovementType.entrada,
          destination: 'Armazém Central',
          responsible: responsible,
          description: description ??
              'Entrada de mercadoria${lot != null && lot.isNotEmpty ? ' (Lote $lot)' : ''}',
          invoiceNumber: invoiceNumber,
        ),
      );

      // Ao dar entrada, reavalia os alertas e limpa avisos críticos antigos caso o produto tenha normalizado
      final currentLevel = product.alertLevel;
      if (currentLevel == StockAlertLevel.normal) {
        _notifications.removeWhere((n) =>
            n.title.contains(product.name) &&
            (n.priority == StockAlertLevel.critico || n.priority == StockAlertLevel.atencao));
        addNotification(
          title: 'Estoque Regularizado: ${product.name}',
          message:
              'Entrada de +${CultivaFormat.number(quantity)} ${product.unit}. Saldo agora de ${CultivaFormat.number(product.currentBalance)} ${product.unit} com status Normal.',
          priority: StockAlertLevel.normal,
        );
      } else if (currentLevel == StockAlertLevel.atencao) {
        _notifications.removeWhere((n) =>
            n.title.contains(product.name) && n.priority == StockAlertLevel.critico);
        addNotification(
          title: 'Estoque em Atenção: ${product.name}',
          message:
              'Entrada de +${CultivaFormat.number(quantity)} ${product.unit}. Saldo elevado para ${CultivaFormat.number(product.currentBalance)} ${product.unit} (Atenção).',
          priority: StockAlertLevel.atencao,
        );
      } else {
        addNotification(
          title: 'Entrada Registrada',
          message:
              '+${CultivaFormat.number(quantity)} ${product.unit} de ${product.name} adicionados ao armazém.',
          priority: StockAlertLevel.normal,
        );
      }

      notifyListeners();
    }
  }

  // Confirmação de lote via Scanner ou OCR com categoria obrigatória
  void confirmBatchFromInvoice({
    required List<Map<String, dynamic>> items,
    required String invoiceNumber,
  }) {
    for (var item in items) {
      final String name = item['name'];
      final double qty = (item['quantity'] as num).toDouble();
      final String? lot = (item['lot'] == null ||
              item['lot'] == 'S/L' ||
              (item['lot'] as String).trim().isEmpty)
          ? null
          : (item['lot'] as String).trim();
      final String? supplier = (item['supplier'] == null ||
              item['supplier'] == 'Fornecedor da NF-e' ||
              (item['supplier'] as String).trim().isEmpty)
          ? null
          : (item['supplier'] as String).trim();
      final DateTime? validity = item['validity'] as DateTime?;
      final double price = (item['unitPrice'] as num?)?.toDouble() ??
          (item['price'] as num?)?.toDouble() ??
          0.0;
      final String unit = item['unit'] ?? 'Sacos';
      final String category = item['category'] ?? kProductCategories.first;

      final existingIndex = _products.indexWhere(
          (p) => p.name.toLowerCase().trim() == name.toLowerCase().trim());

      if (existingIndex != -1) {
        final prod = _products[existingIndex];
        prod.currentBalance += qty;
        prod.history.insert(
          0,
          StockMovement(
            id: 'ocr_${DateTime.now().millisecondsSinceEpoch}_${prod.id}',
            date: DateTime.now(),
            quantity: qty,
            type: MovementType.entrada,
            destination: 'Armazém Central',
            responsible: 'Recepção Fiscal OCR',
            description: 'Recebimento NF-e $invoiceNumber',
            invoiceNumber: invoiceNumber,
          ),
        );
        if (prod.alertLevel == StockAlertLevel.normal) {
          _notifications.removeWhere((n) =>
              n.title.contains(prod.name) &&
              (n.priority == StockAlertLevel.critico || n.priority == StockAlertLevel.atencao));
        } else if (prod.alertLevel == StockAlertLevel.atencao) {
          _notifications.removeWhere((n) =>
              n.title.contains(prod.name) && n.priority == StockAlertLevel.critico);
        }
      } else {
        final double minDays = (item['minimumStockDays'] as num?)?.toDouble() ?? 15.0;
        final String consumptionPeriod = item['consumptionPeriod'] ?? 'Por Mês';
        final newProd = Product(
          id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          description: 'Cadastrado via scanner/nota fiscal',
          category: category,
          currentBalance: qty,
          unit: unit,
          minimumStockDays: minDays,
          consumptionPeriod: consumptionPeriod,
          validity: validity,
          lot: lot,
          supplier: supplier,
          acquisitionPrice: price,
          history: [
            StockMovement(
              id: 'ocr_${DateTime.now().millisecondsSinceEpoch}',
              date: DateTime.now(),
              quantity: qty,
              type: MovementType.entrada,
              destination: 'Armazém Central',
              responsible: 'Recepção Fiscal OCR',
              description: 'Recebimento NF-e $invoiceNumber',
              invoiceNumber: invoiceNumber,
            ),
          ],
        );
        _products.add(newProd);

        // 1. Alerta de Estoque Crítico ou Atenção da NF-e (NUNCA negligenciado)
        if (newProd.stockLevelAlert == StockAlertLevel.critico) {
          addNotification(
            title: 'Estoque Crítico (NF-e): ${newProd.name}',
            message: 'O produto ${newProd.name} deu entrada com saldo de ${CultivaFormat.number(newProd.currentBalance)} ${newProd.unit}, abaixo da meta mínima de ${newProd.minimumStockDays.toInt()} dias.',
            priority: StockAlertLevel.critico,
          );
        } else if (newProd.stockLevelAlert == StockAlertLevel.atencao) {
          addNotification(
            title: 'Atenção ao Estoque (NF-e): ${newProd.name}',
            message: 'O produto ${newProd.name} deu entrada com saldo próximo da meta de segurança (${newProd.minimumStockDays.toInt()} dias).',
            priority: StockAlertLevel.atencao,
          );
        }

        // 2. Alerta de vencimento próximo para novo item cadastrado via scanner/NF-e (<= 30 dias)
        if (newProd.validity != null) {
          final days = newProd.daysUntilExpiry ?? 999;
          if (days <= 30) {
            final String alertTitle;
            final String alertMsg;
            if (days < 0) {
              alertTitle = 'Produto Vencido via NF-e: ${newProd.name}';
              alertMsg = 'O produto ${newProd.name} (Lote: ${newProd.lot ?? 'S/L'}) já está vencido desde ${CultivaFormat.dateOnly(newProd.validity!)}. Verifique o recebimento.';
            } else if (days == 0) {
              alertTitle = 'Vencimento Hoje (NF-e): ${newProd.name}';
              alertMsg = 'O produto ${newProd.name} (Lote: ${newProd.lot ?? 'S/L'}) vence hoje (${CultivaFormat.dateOnly(newProd.validity!)}). Priorize consumo imediato.';
            } else {
              alertTitle = 'Alerta de Vencimento Próximo: ${newProd.name}';
              alertMsg = 'Atenção: ${newProd.name} (Lote: ${newProd.lot ?? 'S/L'}) vence em $days dias (${CultivaFormat.dateOnly(newProd.validity!)}), dentro do prazo de alerta de 30 dias.';
            }
            addNotification(
              title: alertTitle,
              message: alertMsg,
              priority: StockAlertLevel.vencimentoProximo,
            );
          }
        }
      }
    }

    addNotification(
      title: 'Nota Fiscal Confirmada',
      message: 'NF-e $invoiceNumber processada: ${items.length} itens adicionados ao estoque.',
      priority: StockAlertLevel.normal,
    );

    notifyListeners();
  }

  // Ajuste de Inventário / Conferência Física
  void adjustStock({
    required String productId,
    required double newPhysicalBalance,
    required String justification,
    required String responsible,
  }) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final prod = _products[index];
      final diff = newPhysicalBalance - prod.currentBalance;
      prod.currentBalance = newPhysicalBalance;
      prod.history.insert(
        0,
        StockMovement(
          id: 'adj_${DateTime.now().millisecondsSinceEpoch}',
          date: DateTime.now(),
          quantity: diff.abs(),
          type: MovementType.ajuste,
          destination: 'Armazém Central',
          responsible: responsible,
          description: 'Ajuste de inventário físico: $justification (${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(0)} ${prod.unit})',
        ),
      );
      notifyListeners();
    }
  }
}

// ============================================================================
// APP ROOT & TEMA
// ============================================================================

class CultivaStockApp extends StatelessWidget {
  final Widget? home;

  const CultivaStockApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CultivaStock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF1E5631),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E5631),
          primary: const Color(0xFF1E5631),
          surface: const Color(0xFFF8F9FA),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
        ),
      ),
      home: home ?? const MainNavigationScreen(),
    );
  }
}

// ============================================================================
// NAVEGAÇÃO PRINCIPAL (BOTTOM NAVIGATION)
// ============================================================================

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  void switchToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onNavigateToScanner: () => switchToTab(2)),
      const InventoryScreen(),
      const SmartScannerScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          elevation: 0,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF1E5631),
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          type: BottomNavigationBarType.fixed,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Início',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              label: 'Inventário',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner),
              label: 'Scanner',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// COMPONENTE: HEADER COMUM & SISTEMA DE NOTIFICAÇÕES
// ============================================================================

class CultivaStockHeader extends StatelessWidget {
  final String screenSubtitle;

  const CultivaStockHeader({super.key, required this.screenSubtitle});

  @override
  Widget build(BuildContext context) {
    final repo = CultivaStockRepository();

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final hasUnread = repo.hasUnreadNotifications;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.eco, color: Color(0xFF1E5631), size: 22),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CULTIVASTOCK',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 13,
                            color: Color(0xFF1E5631),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          screenSubtitle,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none, color: Colors.black87),
                      if (hasUnread)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () {
                    repo.markNotificationsAsRead();
                    _showNotificationSheet(context, repo);
                  },
                ),
                const SizedBox(width: 4),
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFF1E5631),
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ],
            )
          ],
        );
      },
    );
  }

  void _showNotificationSheet(BuildContext context, CultivaStockRepository repo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final notifs = repo.notifications;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.notifications, color: Color(0xFF1E5631), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Notificações de Campo',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const Divider(),
                  if (notifs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.notifications_off_outlined,
                                size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'Nenhuma notificação no momento',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 320,
                      child: ListView.builder(
                        itemCount: notifs.length,
                        itemBuilder: (context, i) {
                          final n = notifs[i];
                          // Container completo com cor de fundo da prioridade, sem bolinha
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: n.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: n.borderColor, width: 1.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        n.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: n.textColor,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      CultivaFormat.dateTimeShort(n.timestamp),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  n.message,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// TELA 1: INÍCIO (VISÃO OPERACIONAL E TOMADA DE DECISÃO)
// ============================================================================

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToScanner;

  const HomeScreen({super.key, required this.onNavigateToScanner});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedConsumptionCategory = 'Todas';

  @override
  Widget build(BuildContext context) {
    final repo = CultivaStockRepository();

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final products = repo.products;
        final totalUnits = repo.totalStockUnits;
        final totalItemsCount = repo.totalProductsCount;
        final culturesCount = repo.activeCulturesCount;
        final criticalAlerts = repo.criticalAndAttentionProducts;

        // Consumo médio filtrado por categoria dinamicamente
        final filteredWeeklyConsumption =
            repo.calculateWeeklyConsumptionForCategory(_selectedConsumptionCategory);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CultivaStockHeader(screenSubtitle: 'Início'),
                const SizedBox(height: 16),

                // Sub-header protegido contra overflow
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Visão operacional do armazém central',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showSafraManagerModal(context, repo),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E5631).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF1E5631).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 13, color: Color(0xFF1E5631)),
                            const SizedBox(width: 6),
                            Text(
                              repo.currentSafra,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E5631)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF1E5631)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Cards de Resumo Operacional
                Row(
                  children: [
                    // Card Em Estoque (Total Dinâmico)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Em Estoque',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              totalItemsCount == 0
                                  ? '0 itens'
                                  : '$totalItemsCount itens ($culturesCount cat.)',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${CultivaFormat.number(totalUnits)} unidades',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Card Consumo Médio com FILTRO POR CATEGORIA
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Consumo Médio',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.filter_list, size: 18, color: Color(0xFF1E5631)),
                                  tooltip: 'Filtrar Categoria',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onSelected: (cat) {
                                    setState(() {
                                      _selectedConsumptionCategory = cat;
                                    });
                                  },
                                  itemBuilder: (context) {
                                    return ['Todas', ...kProductCategories].map((cat) {
                                      final isSel = cat == _selectedConsumptionCategory;
                                      return PopupMenuItem(
                                        value: cat,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(cat, style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                            if (isSel) const Icon(Icons.check, size: 16, color: Color(0xFF1E5631)),
                                          ],
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ],
                            ),
                            Text(
                              'Cat: $_selectedConsumptionCategory',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              filteredWeeklyConsumption == 0
                                  ? '0 un/sem'
                                  : '${filteredWeeklyConsumption.toStringAsFixed(1)} un/sem',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              filteredWeeklyConsumption > 0
                                  ? 'Calculado via saídas'
                                  : 'Sem saídas registradas',
                              style: TextStyle(
                                color: filteredWeeklyConsumption > 0
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey.shade500,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Seção: AÇÕES RÁPIDAS
                Text(
                  'AÇÕES RÁPIDAS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildQuickActionButton(
                      icon: Icons.add_box_outlined,
                      label: 'Cadastrar\nProduto',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddProductScreen()),
                        );
                      },
                    ),
                    _buildQuickActionButton(
                      icon: Icons.arrow_downward,
                      label: 'Registrar\nSaída',
                      onTap: () {
                        if (products.isEmpty) {
                          _showEmptyStockAlert(context);
                        } else {
                          _showQuickOutflowModal(context);
                        }
                      },
                    ),
                    _buildQuickActionButton(
                      icon: Icons.check_circle_outline,
                      label: 'Conferência\nFísica',
                      onTap: () {
                        if (products.isEmpty) {
                          _showEmptyStockAlert(context);
                        } else {
                          _showAuditModal(context);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Seção: ATENÇÃO AO ESTOQUE (Sem bolinha no header)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ATENÇÃO AO ESTOQUE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                    Text(
                      '${criticalAlerts.length} itens',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Cards de Alerta com cor no Container inteiro e SEM bolinha
                if (criticalAlerts.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                products.isEmpty
                                    ? 'Armazém pronto para cadastro'
                                    : 'Nenhum alerta crítico ativo',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                products.isEmpty
                                    ? 'Adicione produtos manualmente ou via scanner para iniciar o monitoramento.'
                                    : 'Todos os itens cadastrados estão com saldo seguro e giro saudável.',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...criticalAlerts.expand((p) {
                    final alertCards = <Widget>[];

                    // 1. Alerta de Nível de Estoque (Crítico ou Atenção) - NUNCA negligenciado
                    if (p.stockLevelAlert == StockAlertLevel.critico || p.stockLevelAlert == StockAlertLevel.atencao) {
                      final isCrit = p.stockLevelAlert == StockAlertLevel.critico;
                      final String stockSubtitle;
                      if (isCrit) {
                        stockSubtitle = p.averageDailyConsumption > 0
                            ? 'Estoque Crítico: saldo estimado para ${p.estimatedDaysRemaining} dias (meta mín. ${p.minimumStockDays.toInt()}d)'
                            : 'Estoque Crítico: saldo de ${CultivaFormat.number(p.currentBalance)} ${p.unit} (abaixo da meta de ${p.minimumStockDays.toInt()}d)';
                      } else {
                        stockSubtitle = p.averageDailyConsumption > 0
                            ? 'Atenção ao Estoque: saldo estimado para ${p.estimatedDaysRemaining} dias no ritmo atual'
                            : 'Atenção ao Estoque: saldo de ${CultivaFormat.number(p.currentBalance)} ${p.unit} (meta: ${p.minimumStockDays.toInt()}d)';
                      }

                      alertCards.add(
                        _buildAlertCard(
                          context: context,
                          product: p,
                          title: p.name,
                          subtitle: stockSubtitle,
                          overrideLevel: p.stockLevelAlert,
                          overrideBadge: isCrit ? 'ESTOQUE CRÍTICO' : 'ESTOQUE ATENÇÃO',
                        ),
                      );
                    }

                    // 2. Alerta de Vencimento Próximo (≤ 30 dias) - NUNCA negligenciado
                    if (p.hasExpiryRisk) {
                      final lotText = (p.lot != null && p.lot!.isNotEmpty && p.lot != 'S/L') ? 'lote ${p.lot} ' : '';
                      final days = p.daysUntilExpiry ?? 0;
                      final dateStr = p.validity != null ? ' (${CultivaFormat.dateOnly(p.validity!)})' : '';
                      final String expirySubtitle;
                      if (days < 0) {
                        expirySubtitle = 'Produto Vencido: ${lotText}venceu há ${days.abs()} dias$dateStr';
                      } else if (days == 0) {
                        expirySubtitle = 'Vencimento Hoje: ${lotText}vence hoje$dateStr';
                      } else {
                        expirySubtitle = 'Risco de Vencimento: ${lotText}vence em $days dias$dateStr (≤ 30 dias)';
                      }

                      alertCards.add(
                        _buildAlertCard(
                          context: context,
                          product: p,
                          title: p.name,
                          subtitle: expirySubtitle,
                          overrideLevel: StockAlertLevel.vencimentoProximo,
                          overrideBadge: 'RISCO VENC.',
                        ),
                      );
                    }

                    // 3. Fallback para excesso de estoque caso aplicável
                    if (alertCards.isEmpty && p.stockLevelAlert == StockAlertLevel.excesso) {
                      alertCards.add(
                        _buildAlertCard(
                          context: context,
                          product: p,
                          title: p.name,
                          subtitle: 'Saldo em excesso: giro lento e capital imobilizado.',
                          overrideLevel: StockAlertLevel.excesso,
                          overrideBadge: 'EXCESSO',
                        ),
                      );
                    }

                    return alertCards;
                  }),
                const SizedBox(height: 16),

                // Banner OCR / Leitura de Lote
                GestureDetector(
                  onTap: widget.onNavigateToScanner,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.document_scanner_outlined,
                            color: Color(0xFF1E5631),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Leitura de Lote por OCR',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Escaneie notas fiscais ou sacarias',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E5631),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEmptyStockAlert(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Cadastre ao menos um produto para movimentar o estoque.'),
        action: SnackBarAction(
          label: 'Cadastrar',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddProductScreen()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1E5631), size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // Card de Alerta: Cor de fundo no Container Inteiro e SEM Bolinha (Correção 1)
  Widget _buildAlertCard({
    required BuildContext context,
    required Product product,
    required String title,
    required String subtitle,
    StockAlertLevel? overrideLevel,
    String? overrideBadge,
  }) {
    final effectiveLevel = overrideLevel ?? product.alertLevel;
    final isCritical = effectiveLevel == StockAlertLevel.critico;
    final isWarning = effectiveLevel == StockAlertLevel.atencao || effectiveLevel == StockAlertLevel.vencimentoProximo;
    final bgColor = isCritical
        ? const Color(0xFFFFEBEE)
        : (isWarning ? const Color(0xFFFFF3E0) : const Color(0xFFE1F5FE));
    final borderColor = isCritical
        ? const Color(0xFFEF9A9A)
        : (isWarning ? const Color(0xFFFFCC80) : const Color(0xFF81D4FA));
    final primaryColor = isCritical
        ? const Color(0xFFC62828)
        : (isWarning ? const Color(0xFFE65100) : const Color(0xFF0277BD));
    final icon = isCritical
        ? Icons.error_outline
        : (isWarning ? Icons.warning_amber_rounded : Icons.info_outline);
    final badgeLabel = overrideBadge ?? product.stockStatusLabel;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ItemDetailScreen(product: product)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor, // Cor aplicada ao Container/Card INTEIRO
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(icon, color: primaryColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: primaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeLabel.toUpperCase(),
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: primaryColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSafraManagerModal(BuildContext context, CultivaStockRepository repo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (mCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final safras = repo.safras;
            final current = repo.currentSafra;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.calendar_month, color: Color(0xFF1E5631), size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Gerenciar Safras (Por Ano)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(mCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alterne entre safras salvas ou cadastre uma nova safra. O armazém de cada ano permanece salvo.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: safras.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final safra = safras[index];
                          final isSelected = safra == current;
                          final count = repo.getProductCountForSafra(safra);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFE8F3EB) : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSelected ? Icons.check_circle : Icons.agriculture,
                                color: isSelected ? const Color(0xFF1E5631) : Colors.grey.shade600,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              safra,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? const Color(0xFF1E5631) : Colors.black87,
                              ),
                            ),
                            subtitle: Text('$count produtos cadastrados neste período'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  tooltip: 'Editar safra',
                                  onPressed: () {
                                    Navigator.pop(mCtx);
                                    _showEditSafraDialog(context, repo, safra);
                                  },
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E5631),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Ativa',
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              repo.selectSafra(safra);
                              Navigator.pop(mCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Safra alterada para: $safra'),
                                  backgroundColor: const Color(0xFF1E5631),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E5631),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          'Criar Nova Safra (Ano)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.pop(mCtx);
                          _showCreateSafraDialog(context, repo);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateSafraDialog(BuildContext context, CultivaStockRepository repo) {
    final nextYear = DateTime.now().year + repo.safras.length;
    final ctrl = TextEditingController(text: 'Safra $nextYear');

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.add_circle_outline, color: Color(0xFF1E5631), size: 22),
              SizedBox(width: 8),
              Text('Criar Nova Safra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Informe o ano ou nome da nova safra (ex: Safra 2026, Safra 2027). A safra anterior ficará salva.',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome da Safra *',
                  hintText: 'Ex: Safra 2026',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isNotEmpty) {
                  repo.createNewSafra(name);
                  Navigator.pop(dCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Nova safra "$name" criada com sucesso!'),
                      backgroundColor: const Color(0xFF1E5631),
                    ),
                  );
                }
              },
              child: const Text('Criar Safra', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showEditSafraDialog(BuildContext context, CultivaStockRepository repo, String safraToEdit) {
    final ctrl = TextEditingController(text: safraToEdit);

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.edit, color: Color(0xFF1E5631), size: 22),
              SizedBox(width: 8),
              Text('Editar Safra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Altere a identificação ou o ano da safra:',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nome / Ano da Safra',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
              onPressed: () {
                final newName = ctrl.text.trim();
                if (newName.isNotEmpty && newName != safraToEdit) {
                  repo.renameSafra(safraToEdit, newName);
                  Navigator.pop(dCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Safra renomeada para "$newName"!'),
                      backgroundColor: const Color(0xFF1E5631),
                    ),
                  );
                } else {
                  Navigator.pop(dCtx);
                }
              },
              child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showQuickOutflowModal(BuildContext context) {
    final repo = CultivaStockRepository();
    if (repo.products.isEmpty) return;

    Product selectedProduct = repo.products.first;
    final qtyController = TextEditingController();
    final destinationController = TextEditingController(text: 'Plantio • Talhão 01');
    final respController = TextEditingController(text: 'Operador de Campo');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Registrar Baixa / Saída',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<Product>(
                    initialValue: selectedProduct,
                    decoration: InputDecoration(
                      labelText: 'Produto',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: repo.products.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (Saldo: ${p.currentBalance.toInt()} ${p.unit})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedProduct = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantidade (${selectedProduct.unit})',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destinationController,
                    decoration: InputDecoration(
                      labelText: 'Destino / Aplicação (Talhão, Máquina, etc.)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: respController,
                    decoration: InputDecoration(
                      labelText: 'Responsável',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final q = double.tryParse(qtyController.text) ?? 0;
                        if (q > 0) {
                          repo.recordOutflow(
                            productId: selectedProduct.id,
                            quantity: q,
                            destination: destinationController.text,
                            responsible: respController.text,
                            description: 'Saída manual de estoque',
                          );
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Baixa de $q ${selectedProduct.unit} de ${selectedProduct.name} realizada!'),
                              backgroundColor: const Color(0xFF1E5631),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                      label: const Text('Confirmar Baixa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E5631),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAuditModal(BuildContext context) {
    final repo = CultivaStockRepository();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Conferência de Inventário Físico',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Valide o saldo em armazém para reconciliação automática de sobras ou desvios de consumo:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 280,
                child: ListView.builder(
                  itemCount: repo.products.length,
                  itemBuilder: (context, i) {
                    final p = repo.products[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Saldo Sistêmico: ${p.currentBalance.toInt()} ${p.unit}'),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE8F3EB),
                            elevation: 0,
                          ),
                          onPressed: () {
                            _showSingleItemAdjustDialog(context, p);
                          },
                          child: const Text('Auditar', style: TextStyle(color: Color(0xFF1E5631), fontSize: 12)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSingleItemAdjustDialog(BuildContext context, Product p) {
    final controller = TextEditingController(text: p.currentBalance.toInt().toString());
    final justController = TextEditingController(text: 'Contagem física periódica');
    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          title: Text('Ajustar ${p.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Saldo Físico Contado (${p.unit})',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: justController,
                decoration: const InputDecoration(
                  labelText: 'Justificativa do ajuste',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
              onPressed: () {
                final val = double.tryParse(controller.text);
                if (val != null) {
                  CultivaStockRepository().adjustStock(
                    productId: p.id,
                    newPhysicalBalance: val,
                    justification: justController.text,
                    responsible: 'Auditor do Armazém',
                  );
                  Navigator.pop(dCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saldo de ${p.name} atualizado para $val ${p.unit}!')),
                  );
                }
              },
              child: const Text('Salvar Ajuste', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// TELA: ADICIONAR PRODUTO MANUALMENTE
// ============================================================================

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _balanceController = TextEditingController();
  final _lotController = TextEditingController();
  final _supplierController = TextEditingController();
  final _priceController = TextEditingController();
  final _minDaysController = TextEditingController();
  final _invoiceController = TextEditingController();

  String _selectedCategory = kProductCategories.first;
  String _selectedUnit = kProductUnits.first;
  String _selectedConsumptionPeriod = kConsumptionPeriods.first;
  DateTime? _selectedValidity;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _balanceController.dispose();
    _lotController.dispose();
    _supplierController.dispose();
    _priceController.dispose();
    _minDaysController.dispose();
    _invoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Novo Produto',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Identificação do Item',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E5631)),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nome do Produto *',
                  hintText: 'Ex: Ureia 46%, Milho FS-500',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Informe o nome do produto';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Categoria * (Obrigatória)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF1E5631)),
                ),
                items: kProductCategories.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(cat),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: _selectedUnit,
                decoration: InputDecoration(
                  labelText: 'Unidade de Medida *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.straighten, color: Color(0xFF1E5631)),
                ),
                items: kProductUnits.map((u) {
                  return DropdownMenuItem(
                    value: u,
                    child: Text(u),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedUnit = val);
                },
              ),
              const SizedBox(height: 20),

              const Text(
                'Saldo e Preço de Aquisição',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E5631)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _balanceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Saldo Inicial *',
                        hintText: '0',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) {
                        if (val == null || double.tryParse(val.replaceAll(',', '.')) == null) {
                          return 'Informe o saldo';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: r'Preço Unitário (R$) *',
                        hintText: '0.00',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) {
                        if (val == null || double.tryParse(val.replaceAll(',', '.')) == null) {
                          return 'Informe o preço';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _minDaysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Meta de Estoque Mínimo (dias) *',
                  hintText: 'Ex: 15, 30',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  helperText: 'Usado para gerar alerta de estoque crítico (obrigatório)',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Informe a meta de estoque mínimo em dias *';
                  }
                  final parsed = double.tryParse(val.replaceAll(',', '.'));
                  if (parsed == null || parsed <= 0) {
                    return 'Informe um número de dias válido (> 0)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: _selectedConsumptionPeriod,
                decoration: InputDecoration(
                  labelText: 'Medida de Consumo Desejada *',
                  helperText: 'Escolha como deseja visualizar o consumo (ex: milho por mês)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.analytics_outlined, color: Color(0xFF1E5631)),
                ),
                items: kConsumptionPeriods.map((period) {
                  return DropdownMenuItem(
                    value: period,
                    child: Text(period),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedConsumptionPeriod = val);
                },
              ),
              const SizedBox(height: 20),

              const Text(
                'Rastreabilidade e Fiscal',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E5631)),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _lotController,
                      decoration: InputDecoration(
                        labelText: 'Lote',
                        hintText: 'Ex: L-1026',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormField<DateTime>(
                      initialValue: _selectedValidity,
                      validator: (val) {
                        if (_selectedValidity == null) {
                          return 'Data de vencimento obrigatória *';
                        }
                        return null;
                      },
                      builder: (formFieldState) {
                        final hasError = formFieldState.hasError;
                        final daysLeft = _selectedValidity != null
                            ? DateTime(_selectedValidity!.year, _selectedValidity!.month, _selectedValidity!.day)
                                .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
                                .inDays
                            : null;
                        final isNearExpiry = daysLeft != null && daysLeft <= 30;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedValidity ?? DateTime.now().add(const Duration(days: 90)),
                                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                                );
                                if (picked != null) {
                                  setState(() => _selectedValidity = picked);
                                  formFieldState.didChange(picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Data de Vencimento *',
                                  labelStyle: TextStyle(
                                    color: hasError
                                        ? Colors.red.shade700
                                        : (isNearExpiry ? const Color(0xFFE65100) : null),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: hasError
                                          ? Colors.red
                                          : (isNearExpiry ? const Color(0xFFE65100) : Colors.grey.shade400),
                                      width: (hasError || isNearExpiry) ? 1.5 : 1.0,
                                    ),
                                  ),
                                  errorText: formFieldState.errorText,
                                  suffixIcon: Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                    color: hasError
                                        ? Colors.red
                                        : (isNearExpiry ? const Color(0xFFE65100) : const Color(0xFF1E5631)),
                                  ),
                                ),
                                child: Text(
                                  _selectedValidity != null
                                      ? CultivaFormat.dateOnly(_selectedValidity!)
                                      : 'Selecione a data *',
                                  style: TextStyle(
                                    color: _selectedValidity != null ? Colors.black87 : Colors.grey.shade600,
                                    fontWeight: _selectedValidity != null ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                            if (isNearExpiry)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, left: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFE65100)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        daysLeft < 0
                                            ? 'Produto já vencido há ${daysLeft.abs()} dias!'
                                            : daysLeft == 0
                                                ? 'Atenção: Vence hoje!'
                                                : 'Atenção: Vence em $daysLeft dias (≤ 30 dias)! Alerta será gerado.',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFE65100),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _supplierController,
                decoration: InputDecoration(
                  labelText: 'Fornecedor',
                  hintText: 'Ex: AgroVale, Fertilizantes Brasil',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _invoiceController,
                decoration: InputDecoration(
                  labelText: 'Número da NF-e / Recibo (Opcional)',
                  hintText: 'Ex: NF-e 00045',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Descrição / Detalhes Adicionais',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saveProduct,
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text(
                    'Salvar e Adicionar ao Armazém',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E5631),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _saveProduct() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_selectedValidity == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A data de vencimento é obrigatória!'),
            backgroundColor: Color(0xFFD32F2F),
          ),
        );
        return;
      }

      final balance = double.parse(_balanceController.text.replaceAll(',', '.'));
      final price = double.parse(_priceController.text.replaceAll(',', '.'));
      final minDays = double.parse(_minDaysController.text.replaceAll(',', '.'));

      final lotText = _lotController.text.trim();
      final supplierText = _supplierController.text.trim();

      final newProduct = Product(
        id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        currentBalance: balance,
        unit: _selectedUnit,
        minimumStockDays: minDays,
        consumptionPeriod: _selectedConsumptionPeriod,
        validity: _selectedValidity,
        lot: lotText.isNotEmpty ? lotText : null,
        supplier: supplierText.isNotEmpty ? supplierText : null,
        acquisitionPrice: price,
        history: [
          if (balance > 0)
            StockMovement(
              id: 'init_${DateTime.now().millisecondsSinceEpoch}',
              date: DateTime.now(),
              quantity: balance,
              type: MovementType.entrada,
              destination: 'Armazém Central',
              responsible: 'Cadastro Manual',
              description: 'Saldo inicial cadastrado',
              invoiceNumber: _invoiceController.text.trim().isNotEmpty ? _invoiceController.text.trim() : null,
            ),
        ],
      );

      CultivaStockRepository().addProduct(newProduct);

      final days = newProduct.daysUntilExpiry ?? 999;
      final isNearExpiry = days <= 30;

      Navigator.pop(context);

      if (isNearExpiry) {
        showDialog(
          context: context,
          builder: (dCtx) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 24),
                  SizedBox(width: 8),
                  Text('Alerta de Vencimento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Text(
                days < 0
                    ? 'O produto "${newProduct.name}" foi cadastrado, mas está VENCIDO há ${days.abs()} dias (${CultivaFormat.dateOnly(newProduct.validity!)}).\n\nUm alerta crítico foi registrado no painel de notificações.'
                    : days == 0
                        ? 'O produto "${newProduct.name}" foi cadastrado, mas VENCE HOJE (${CultivaFormat.dateOnly(newProduct.validity!)}).\n\nUm alerta de consumo imediato foi emitido no painel de notificações.'
                        : 'O produto "${newProduct.name}" foi cadastrado, mas está próximo da data de vencimento (vence em $days dias, limite de alerta de 30 dias)!\n\nData de validade: ${CultivaFormat.dateOnly(newProduct.validity!)}.\n\nUm alerta foi emitido no painel de notificações.',
                style: const TextStyle(fontSize: 14),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('OK, Entendido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newProduct.name} cadastrado com sucesso!'),
            backgroundColor: const Color(0xFF1E5631),
          ),
        );
      }
    }
  }
}

// ============================================================================
// TELA 2: INVENTÁRIO (LISTAGEM, BUSCA, ENTRADA [+] E SAÍDA [-])
// ============================================================================

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _selectedCategory = 'Todos';
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final repo = CultivaStockRepository();

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final allProducts = repo.products;

        final filteredProducts = allProducts.where((p) {
          final matchesCategory = _selectedCategory == 'Todos' ||
              p.category.toLowerCase() == _selectedCategory.toLowerCase();
          final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (p.lot != null && p.lot!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
              p.category.toLowerCase().contains(_searchQuery.toLowerCase());
          return matchesCategory && matchesSearch;
        }).toList();

        final filterCategories = ['Todos', ...kProductCategories];

        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  children: [
                    const CultivaStockHeader(screenSubtitle: 'Inventário'),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Inventário',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${filteredProducts.length} itens',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isSearching ? Icons.close : Icons.search,
                                color: Colors.black87,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isSearching = !_isSearching;
                                  if (!_isSearching) {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  }
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Color(0xFF1E5631), size: 28),
                              tooltip: 'Novo Produto',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AddProductScreen()),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (_isSearching) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Buscar por produto, lote ou categoria...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        onChanged: (text) => setState(() => _searchQuery = text),
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filterCategories.length,
                  itemBuilder: (context, index) {
                    final cat = filterCategories[index];
                    final isSelected = cat == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        selectedColor: const Color(0xFF1E5631),
                        backgroundColor: Colors.white,
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF1E5631) : Colors.grey.shade300,
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: filteredProducts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                allProducts.isEmpty
                                    ? 'Seu estoque está vazio'
                                    : 'Nenhum item encontrado nesta categoria',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                allProducts.isEmpty
                                    ? 'Adicione seus produtos reais manualmente ou escaneie uma nota fiscal para começar.'
                                    : 'Tente alterar os filtros ou o termo de busca.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                              if (allProducts.isEmpty) ...[
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AddProductScreen()),
                                    );
                                  },
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  label: const Text('Cadastrar Primeiro Produto', style: TextStyle(color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E5631),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final p = filteredProducts[index];
                          return _buildInventoryItemCard(context, p, repo);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInventoryItemCard(BuildContext context, Product p, CultivaStockRepository repo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ItemDetailScreen(product: p)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('• ${p.category}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${CultivaFormat.number(p.currentBalance)} ${p.unit}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: p.statusBackgroundColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: p.statusColor.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            p.stockStatusLabel,
                            style: TextStyle(
                              color: p.statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      _showFastDecrementDialog(context, p, repo);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Icon(Icons.remove, color: Colors.black87, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _showFastIncrementDialog(context, p, repo);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F3EB),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1E5631).withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.add, color: Color(0xFF1E5631), size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFastDecrementDialog(BuildContext context, Product p, CultivaStockRepository repo) {
    final qtyController = TextEditingController(text: '1');
    final talhaoController = TextEditingController(text: 'Plantio • Talhão 01');

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Baixa Rápida: ${p.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Saldo atual: ${p.currentBalance.toInt()} ${p.unit}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quantidade a retirar (${p.unit})',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: talhaoController,
                decoration: InputDecoration(
                  labelText: 'Destino / Talhão',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E5631),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final qty = double.tryParse(qtyController.text) ?? 0;
                if (qty > 0) {
                  repo.recordOutflow(
                    productId: p.id,
                    quantity: qty,
                    destination: talhaoController.text,
                    responsible: 'Operador de Campo',
                    description: 'Baixa rápida registrada no inventário',
                  );
                  Navigator.pop(dCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Baixa de $qty ${p.unit} realizada! Saldo e consumo atualizados.'),
                      backgroundColor: const Color(0xFF1E5631),
                    ),
                  );
                }
              },
              child: const Text('Confirmar Baixa', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showFastIncrementDialog(BuildContext context, Product p, CultivaStockRepository repo) {
    final qtyController = TextEditingController(text: '10');
    final originController = TextEditingController(text: 'Compra / Reposição');

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.add_circle, color: Color(0xFF1E5631)),
              const SizedBox(width: 8),
              Expanded(child: Text('Entrada: ${p.name}')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Saldo atual: ${p.currentBalance.toInt()} ${p.unit}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quantidade a adicionar (${p.unit})',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: originController,
                decoration: InputDecoration(
                  labelText: 'Origem / Motivo da Entrada',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E5631),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final qty = double.tryParse(qtyController.text) ?? 0;
                if (qty > 0) {
                  repo.recordInflow(
                    productId: p.id,
                    quantity: qty,
                    supplier: p.supplier,
                    lot: p.lot,
                    responsible: 'Operador de Armazém',
                    description: originController.text,
                  );
                  Navigator.pop(dCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Entrada de +$qty ${p.unit} realizada com sucesso!'),
                      backgroundColor: const Color(0xFF1E5631),
                    ),
                  );
                }
              },
              child: const Text('Confirmar Entrada', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// TELA 3: SMART SCANNER (CÂMERA LIMPA, EDIÇÃO E REMOÇÃO DE PRODUTOS)
// ============================================================================

class SmartScannerScreen extends StatefulWidget {
  const SmartScannerScreen({super.key});

  @override
  State<SmartScannerScreen> createState() => _SmartScannerScreenState();
}

class _SmartScannerScreenState extends State<SmartScannerScreen> {
  int _selectedScannerTab = 0;
  bool _isFlashOn = false;
  bool _isProcessing = false;

  // Itens em revisão prontos para edição e remoção confirmada
  List<Map<String, dynamic>> _scannedItems = [
    {
      'name': 'Milho Híbrido FS-500',
      'quantity': 100.0,
      'unit': 'Sacos',
      'lot': 'ML-1026',
      'category': 'Sementes',
      'supplier': 'AgroVale',
      'unitPrice': 420.0,
      'totalPrice': 42000.0,
      'validity': DateTime.now().add(const Duration(days: 90)),
      'minimumStockDays': null, // Obrigatório preenchimento pelo usuário antes de salvar
      'consumptionPeriod': 'Por Mês',
    },
    {
      'name': 'Soja Monsoy 5947',
      'quantity': 50.0,
      'unit': 'Sacos',
      'lot': 'SJ-8840',
      'category': 'Sementes',
      'supplier': 'Sementes Goiás',
      'unitPrice': 500.0,
      'totalPrice': 25000.0,
      'validity': DateTime.now().add(const Duration(days: 5)), // Vence em 5 dias (≤ 30 dias) -> Dispara Alerta
      'minimumStockDays': null, // Obrigatório preenchimento pelo usuário antes de salvar
      'consumptionPeriod': 'Por Mês',
    },
    {
      'name': 'Herbicida Glifosato 480',
      'quantity': 20.0,
      'unit': 'Litros',
      'lot': 'HB-3109',
      'category': 'Defensivos',
      'supplier': 'Syngenta Agro',
      'unitPrice': 190.0,
      'totalPrice': 3800.0,
      'validity': DateTime.now().add(const Duration(days: 180)),
      'minimumStockDays': null, // Obrigatório preenchimento pelo usuário antes de salvar
      'consumptionPeriod': 'Por Mês',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: CultivaStockHeader(screenSubtitle: 'Scanner'),
              ),

              // Viewfinder Container da Câmera (Sem texto fictício sobreposto - Requisito 3)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 290,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2229),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.document_scanner, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Smart Scanner',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 20),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),

                    // Abas com proteção contra overflow
                    Positioned(
                      top: 50,
                      left: 20,
                      right: 20,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedScannerTab = 0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _selectedScannerTab == 0 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.receipt_long,
                                          size: 15,
                                          color: _selectedScannerTab == 0 ? Colors.black87 : Colors.white70,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Nota Fiscal',
                                            style: TextStyle(
                                              color: _selectedScannerTab == 0 ? Colors.black87 : Colors.white70,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedScannerTab = 1),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _selectedScannerTab == 1 ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Código de Barras',
                                      style: TextStyle(
                                        color: _selectedScannerTab == 1 ? Colors.black87 : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Viewfinder Limpo: Apenas moldura e guias de escaneamento (Requisito 3)
                    Positioned(
                      top: 96,
                      left: 20,
                      right: 20,
                      bottom: 58,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF14171E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24, width: 1.2),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Positioned(
                              top: 10,
                              left: 10,
                              child: Text('┌', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 26, fontWeight: FontWeight.bold)),
                            ),
                            const Positioned(
                              top: 10,
                              right: 10,
                              child: Text('┐', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 26, fontWeight: FontWeight.bold)),
                            ),
                            const Positioned(
                              bottom: 10,
                              left: 10,
                              child: Text('└', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 26, fontWeight: FontWeight.bold)),
                            ),
                            const Positioned(
                              bottom: 10,
                              right: 10,
                              child: Text('┘', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 26, fontWeight: FontWeight.bold)),
                            ),
                            // Linha de laser centralizada sem textos fictícios
                            Container(
                              height: 1.5,
                              margin: const EdgeInsets.symmetric(horizontal: 28),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF66BB6A).withValues(alpha: 0.0),
                                    const Color(0xFF66BB6A),
                                    const Color(0xFF66BB6A).withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 10,
                      left: 20,
                      right: 20,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IconButton(
                            icon: Icon(
                              _isFlashOn ? Icons.flash_on : Icons.flash_off,
                              color: Colors.white70,
                              size: 22,
                            ),
                            onPressed: () {
                              setState(() => _isFlashOn = !_isFlashOn);
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              _simulateCapture();
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E5631),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.image_outlined, color: Colors.white70, size: 22),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Abrindo galeria de notas fiscais...')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Painel de Revisão com Edição e Remoção de Itens (Requisito 2 e 5)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Revisar leitura',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          '${_scannedItems.length} itens identificados na nota',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () => _showEditScannedItemsModal(context),
                      icon: const Icon(Icons.edit, size: 14, color: Color(0xFF1E5631)),
                      label: const Text('Editar Tudo', style: TextStyle(color: Color(0xFF1E5631), fontWeight: FontWeight.bold, fontSize: 13)),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE8F3EB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              if (_scannedItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('Nenhum item pendente de revisão', style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _resetMockScannedItems,
                          child: const Text('Simular Nova Leitura de NF-e'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: _scannedItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;

                      final double qty = (item['quantity'] as num).toDouble();
                      final String name = item['name'];
                      final String unit = item['unit'];
                      final String lot = item['lot'];
                      final String cat = item['category'];
                      final double total = (item['totalPrice'] as num).toDouble();
                      final double unitPrice = (item['unitPrice'] as num).toDouble();

                      final DateTime? validity = item['validity'] as DateTime?;
                      final double? minDays = (item['minimumStockDays'] as num?)?.toDouble();
                      final String period = item['consumptionPeriod'] ?? 'Por Mês';

                      final int? daysUntilExp = validity != null
                          ? DateTime(validity.year, validity.month, validity.day)
                              .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
                              .inDays
                          : null;
                      final bool isNearExpiry = daysUntilExp != null && daysUntilExp <= 30;
                      final bool isMissingMinDays = minDays == null || minDays <= 0;
                      final bool isMissingValidity = validity == null;
                      final bool hasPendingRequired = isMissingMinDays || isMissingValidity;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasPendingRequired
                                ? const Color(0xFFEF9A9A)
                                : (isNearExpiry ? const Color(0xFFFFCC80) : Colors.grey.shade200),
                            width: (hasPendingRequired || isNearExpiry) ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasPendingRequired
                                  ? Icons.error_outline
                                  : (isNearExpiry ? Icons.warning_amber_rounded : Icons.check_circle),
                              color: hasPendingRequired
                                  ? const Color(0xFFD32F2F)
                                  : (isNearExpiry ? const Color(0xFFE65100) : const Color(0xFF2E7D32)),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${qty.toInt()}x $unit - $name',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Lote $lot • $cat',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  if (validity != null)
                                    Row(
                                      children: [
                                        Icon(
                                          isNearExpiry ? Icons.access_time : Icons.event_available,
                                          size: 13,
                                          color: isNearExpiry ? const Color(0xFFE65100) : const Color(0xFF1E5631),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Venc: ${CultivaFormat.dateOnly(validity)}${isNearExpiry ? (daysUntilExp < 0 ? ' (Vencido!)' : daysUntilExp == 0 ? ' (Vence hoje!)' : ' (Restam $daysUntilExp d - Alerta!)') : ''}',
                                            style: TextStyle(
                                              color: isNearExpiry ? const Color(0xFFE65100) : Colors.grey.shade700,
                                              fontSize: 11,
                                              fontWeight: isNearExpiry ? FontWeight.bold : FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      children: const [
                                        Icon(Icons.error_outline, size: 13, color: Color(0xFFD32F2F)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Vencimento obrigatório pendente',
                                          style: TextStyle(color: Color(0xFFD32F2F), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 2),
                                  if (isMissingMinDays)
                                    Row(
                                      children: const [
                                        Icon(Icons.assignment_late_outlined, size: 13, color: Color(0xFFD32F2F)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Meta estoque mín. pendente *',
                                          style: TextStyle(color: Color(0xFFD32F2F), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      children: [
                                        const Icon(Icons.rule, size: 13, color: Color(0xFF1E5631)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Meta mín: ${minDays.toInt()} dias • Medida: $period',
                                            style: TextStyle(color: Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  CultivaFormat.currency(total),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  '${CultivaFormat.currency(unitPrice)}/un',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                ),
                              ],
                            ),
                            // Botão de Edição
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 19, color: Colors.black54),
                              tooltip: 'Editar este item',
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () => _showSingleItemEditDialog(context, index),
                            ),
                            const SizedBox(width: 4),
                            // Botão de Exclusão com Dialog Destrutivo (Requisito 2)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFD32F2F)),
                              tooltip: 'Remover este produto',
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () => _showDeleteItemConfirmationDialog(context, index),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.verified, color: Color(0xFF2E7D32), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'CNPJ emissor e itens validados com sucesso',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_scannedItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _confirmAndAddAll,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check, color: Colors.white),
                      label: Text(
                        _isProcessing ? 'Processando Entrada...' : 'Confirmar e Adicionar Tudo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E5631),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Dialog de Confirmação com Botão Destrutivo Vermelho (Requisito 2)
  void _showDeleteItemConfirmationDialog(BuildContext context, int index) {
    final item = _scannedItems[index];
    final String itemName = item['name'] ?? 'este produto';

    showDialog(
      context: context,
      builder: (dCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.delete_outline, color: Color(0xFFD32F2F), size: 22),
              SizedBox(width: 8),
              Text('Remover Produto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: const Text(
            'Tem certeza que deseja remover este produto da lista?',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                setState(() {
                  _scannedItems.removeAt(index);
                });
                Navigator.pop(dCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$itemName removido da lista de revisão.'),
                    backgroundColor: const Color(0xFFD32F2F),
                  ),
                );
              },
              child: const Text('Remover', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _resetMockScannedItems() {
    setState(() {
      _scannedItems = [
        {
          'name': 'Adubo NPK 04-14-08',
          'quantity': 200.0,
          'unit': 'Sacos',
          'lot': 'NPK-883',
          'category': 'Fertilizantes',
          'supplier': 'Fertilizantes Brasil',
          'unitPrice': 165.0,
          'totalPrice': 33000.0,
          'validity': DateTime.now().add(const Duration(days: 180)),
          'minimumStockDays': null,
          'consumptionPeriod': 'Por Mês',
        },
        {
          'name': 'Óleo Diesel S10',
          'quantity': 1500.0,
          'unit': 'Litros',
          'lot': 'DSL-2026',
          'category': 'Combustíveis',
          'supplier': 'Petrobras Distribuidora',
          'unitPrice': 6.20,
          'totalPrice': 9300.0,
          'validity': DateTime.now().add(const Duration(days: 6)), // 6 dias (≤ 30 dias) -> Dispara Alerta
          'minimumStockDays': null,
          'consumptionPeriod': 'Por Mês',
        },
      ];
    });
  }

  void _simulateCapture() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Foto capturada! Lendo dados fiscais via OCR...'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _confirmAndAddAll() async {
    // 1. Validação estrita: Meta de Estoque Mínimo e Data de Vencimento OBRIGATÓRIAS em todos os itens
    final pendingItems = <String>[];
    for (var item in _scannedItems) {
      final name = (item['name'] as String?)?.trim() ?? '';
      final validity = item['validity'] as DateTime?;
      final minDays = (item['minimumStockDays'] as num?)?.toDouble();
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unitPrice'] as num?)?.toDouble();

      final missing = <String>[];
      if (minDays == null || minDays <= 0) {
        missing.add('Meta de Estoque Mínimo');
      }
      if (validity == null) {
        missing.add('Data de Vencimento');
      }
      if (name.isEmpty) missing.add('Nome do Produto');
      if (qty <= 0) missing.add('Quantidade (> 0)');
      if (price == null || price < 0) missing.add('Preço');

      if (missing.isNotEmpty) {
        pendingItems.add('• ${name.isEmpty ? "Item sem nome" : name}: pendente de ${missing.join(", ")}');
      }
    }

    if (pendingItems.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.error_outline, color: Color(0xFFD32F2F), size: 22),
                SizedBox(width: 8),
                Text('Preenchimento Obrigatório', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Text(
              'Atenção: A Meta de Estoque Mínimo e a Data de Validade devem ser obrigatoriamente preenchidas para todos os produtos captados pelo scanner!\n\n'
              'Itens com pendências obrigatórias:\n'
              '${pendingItems.join('\n')}\n\n'
              'Clique no botão de edição (lápis) de cada produto para preencher a Meta de Estoque Mínimo, a Medida de Consumo e a Validade.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
      return;
    }

    // Identifica itens com vencimento próximo (mínimo de 30 dias: <= 30 dias)
    final nearExpiryItems = _scannedItems.where((item) {
      final val = item['validity'] as DateTime?;
      if (val == null) return false;
      final days = DateTime(val.year, val.month, val.day)
          .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
          .inDays;
      return days <= 30;
    }).toList();

    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final repo = CultivaStockRepository();
    repo.confirmBatchFromInvoice(
      items: _scannedItems,
      invoiceNumber: '00045',
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _scannedItems = [];
      });

      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF1E5631)),
                SizedBox(width: 8),
                Text('Entrada Concluída!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Os itens foram adicionados ao armazém com sucesso!\n'
                  'Saldos, metas de estoque mínimo, medidas de consumo e alertas foram recalculados automaticamente.',
                ),
                if (nearExpiryItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCC80)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Alerta de Vencimento Emitido',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100), fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'O(s) seguinte(s) produto(s) possuem vencimento próximo (≤ 30 dias) e geraram alertas no sistema:\n'
                          '${nearExpiryItems.map((i) {
                            final val = i['validity'] as DateTime;
                            final days = DateTime(val.year, val.month, val.day)
                                .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
                                .inDays;
                            return "• ${i['name']} (Vence em $days dias - ${CultivaFormat.dateOnly(val)})";
                          }).join('\n')}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    }
  }

  void _showSingleItemEditDialog(BuildContext context, int index) {
    final item = _scannedItems[index];

    final nameCtrl = TextEditingController(text: item['name']);
    final qtyCtrl = TextEditingController(text: item['quantity'].toString());
    final lotCtrl = TextEditingController(text: item['lot']);
    final priceCtrl = TextEditingController(text: item['unitPrice'].toString());
    final supplierCtrl = TextEditingController(text: item['supplier']);
    final minDaysCtrl = TextEditingController(
      text: item['minimumStockDays'] != null ? item['minimumStockDays'].toString() : '',
    );
    String selectedCat = item['category'] ?? kProductCategories.first;
    String selectedUnit = item['unit'] ?? kProductUnits.first;
    String selectedConsumptionPeriod = item['consumptionPeriod'] ?? 'Por Mês';
    DateTime? selectedValidity = item['validity'] as DateTime?;
    String? validityError;
    String? minDaysError;

    showDialog(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Editar Item do Scanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nome do Produto *'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCat,
                      decoration: const InputDecoration(labelText: 'Categoria * (Obrigatória)'),
                      items: kProductCategories.map((cat) {
                        return DropdownMenuItem(value: cat, child: Text(cat));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCat = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Quantidade *'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedUnit,
                            decoration: const InputDecoration(labelText: 'Unidade *'),
                            items: kProductUnits.map((u) {
                              return DropdownMenuItem(value: u, child: Text(u));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => selectedUnit = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: r'Preço Unitário (R$) *'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: lotCtrl,
                            decoration: const InputDecoration(labelText: 'Lote'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: supplierCtrl,
                      decoration: const InputDecoration(labelText: 'Fornecedor'),
                    ),
                    const SizedBox(height: 10),

                    // Campo Obrigatório de Meta de Estoque Mínimo
                    TextField(
                      controller: minDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Meta de Estoque Mínimo (dias) * (Obrigatória)',
                        hintText: 'Ex: 15, 30',
                        errorText: minDaysError,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.rule, size: 18),
                      ),
                      onChanged: (val) {
                        if (minDaysError != null) {
                          setDialogState(() => minDaysError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // Campo de Medida de Consumo (Por Mês, Por Semana, Por Dia)
                    DropdownButtonFormField<String>(
                      initialValue: selectedConsumptionPeriod,
                      decoration: InputDecoration(
                        labelText: 'Medida de Consumo Desejada *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.analytics_outlined, size: 18),
                      ),
                      items: kConsumptionPeriods.map((period) {
                        return DropdownMenuItem(
                          value: period,
                          child: Text(period),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedConsumptionPeriod = val);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // Campo Obrigatório de Data de Vencimento
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedValidity ?? DateTime.now().add(const Duration(days: 90)),
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedValidity = picked;
                            validityError = null;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Data de Vencimento * (Obrigatória)',
                          errorText: validityError,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          suffixIcon: const Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          selectedValidity != null
                              ? CultivaFormat.dateOnly(selectedValidity!)
                              : 'Selecione a data de vencimento *',
                          style: TextStyle(
                            color: selectedValidity != null ? Colors.black87 : Colors.grey.shade600,
                            fontWeight: selectedValidity != null ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    if (selectedValidity != null)
                      Builder(builder: (ctx) {
                        final days = DateTime(selectedValidity!.year, selectedValidity!.month, selectedValidity!.day)
                            .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
                            .inDays;
                        if (days <= 30) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4, left: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFE65100)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    days < 0
                                        ? 'Produto já vencido há ${days.abs()} dias!'
                                        : days == 0
                                            ? 'Vence hoje! (Consumo imediato)'
                                            : 'Vence em $days dias (≤ 30 dias)! Gerará alerta.',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E5631)),
                  onPressed: () {
                    final trimmedName = nameCtrl.text.trim();
                    if (trimmedName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('O nome do produto é obrigatório!'),
                          backgroundColor: Color(0xFFD32F2F),
                        ),
                      );
                      return;
                    }

                    final parsedMinDays = double.tryParse(minDaysCtrl.text.trim().replaceAll(',', '.'));
                    if (parsedMinDays == null || parsedMinDays <= 0) {
                      setDialogState(() {
                        minDaysError = 'A meta de estoque mínimo é obrigatória (> 0) *';
                      });
                      return;
                    }

                    if (selectedValidity == null) {
                      setDialogState(() {
                        validityError = 'A data de vencimento é obrigatória *';
                      });
                      return;
                    }

                    final newQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? item['quantity'];
                    final newPrice = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? item['unitPrice'];

                    setState(() {
                      _scannedItems[index] = {
                        'name': trimmedName,
                        'quantity': newQty,
                        'unit': selectedUnit,
                        'lot': lotCtrl.text.trim(),
                        'category': selectedCat,
                        'supplier': supplierCtrl.text.trim(),
                        'unitPrice': newPrice,
                        'totalPrice': newQty * newPrice,
                        'validity': selectedValidity,
                        'minimumStockDays': parsedMinDays,
                        'consumptionPeriod': selectedConsumptionPeriod,
                      };
                    });

                    Navigator.pop(dCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Dados do item atualizados com sucesso!')),
                    );
                  },
                  child: const Text('Salvar', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditScannedItemsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Editar Itens da Nota',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const SizedBox(height: 8),
              const Text('Selecione um item para editar seus dados antes de confirmar:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              ..._scannedItems.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final DateTime? itemVal = item['validity'] as DateTime?;
                final valText = itemVal != null ? CultivaFormat.dateOnly(itemVal) : 'Sem validade (obrigatório)';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note, color: Color(0xFF1E5631)),
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${item['quantity']} ${item['unit']} • Lote: ${item['lot']} • ${item['category']} • Venc: $valText'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFD32F2F), size: 20),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showDeleteItemConfirmationDialog(context, idx);
                        },
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSingleItemEditDialog(context, idx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// TELA 4: DETALHES DO ITEM (ANÁLISE PROFUNDA, RISCOS, CUSTO E MOVIMENTAÇÃO)
// ============================================================================

class ItemDetailScreen extends StatelessWidget {
  final Product product;

  const ItemDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final repo = CultivaStockRepository();

    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final currentProduct = repo.products.firstWhere(
          (p) => p.id == product.id,
          orElse: () => product,
        );

        final daysLeft = currentProduct.estimatedDaysRemaining;
        final weeklyUsage = currentProduct.averageWeeklyConsumption;
        final capitalInvested = currentProduct.totalInvestedCapital;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Detalhes Do Item',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            centerTitle: true,
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFF1E5631),
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentProduct.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentProduct.description.isNotEmpty
                                ? currentProduct.description
                                : currentProduct.category,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'SALDO ATUAL',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${CultivaFormat.number(currentProduct.currentBalance)} ${currentProduct.unit}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(child: _buildInfoColumn('CATEGORIA', currentProduct.category)),
                    Expanded(
                      child: _buildInfoColumn(
                        'LOTE',
                        _formatOptional(currentProduct.lot),
                        isMuted: _formatOptional(currentProduct.lot) == 'Não informado',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoColumn(
                        'VALIDADE',
                        _formatValidity(currentProduct.validity),
                        isMuted: currentProduct.validity == null,
                      ),
                    ),
                    Expanded(
                      child: _buildInfoColumn(
                        'FORNECEDOR',
                        _formatOptional(currentProduct.supplier),
                        isMuted: _formatOptional(currentProduct.supplier) == 'Não informado',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoColumn(
                        'META ESTOQUE MÍN.',
                        '${currentProduct.minimumStockDays.toInt()} dias',
                      ),
                    ),
                    Expanded(
                      child: _buildInfoColumn(
                        'MEDIDA DE CONSUMO',
                        currentProduct.consumptionPeriod,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Situação no Armazém',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: currentProduct.statusBackgroundColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          currentProduct.stockStatusLabel,
                          style: TextStyle(
                            color: currentProduct.statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3EB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Color(0xFF1E5631), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              weeklyUsage > 0
                                  ? 'Média de uso: ${currentProduct.averageConsumption.toStringAsFixed(1)} ${currentProduct.unit.toLowerCase()}${currentProduct.consumptionPeriodLabel} (${currentProduct.consumptionPeriod})'
                                  : 'Média de uso: Sem saídas recentes (${currentProduct.consumptionPeriod})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Text(
                          weeklyUsage > 0
                              ? 'Medida configurada: ${currentProduct.consumptionPeriod} • Equivalente: ${(currentProduct.averageDailyConsumption).toStringAsFixed(1)}/dia | ${(currentProduct.averageWeeklyConsumption).toStringAsFixed(1)}/sem | ${(currentProduct.averageDailyConsumption * 30.0).toStringAsFixed(1)}/mês'
                              : 'Registre saídas para calcular a taxa média de uso conforme a medida escolhida (${currentProduct.consumptionPeriod})',
                          style: const TextStyle(color: Colors.black54, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Card de Projeção com Cor Dinâmica conforme a Situação/Alerta do Estoque
                Builder(
                  builder: (context) {
                    final Color projectionBg;
                    final Color projectionBorder;
                    final Color projectionText;
                    final IconData projectionIcon;

                    switch (currentProduct.alertLevel) {
                      case StockAlertLevel.critico:
                        projectionBg = const Color(0xFFFFEBEE);
                        projectionBorder = const Color(0xFFEF9A9A);
                        projectionText = const Color(0xFFC62828);
                        projectionIcon = Icons.error_outline;
                        break;
                      case StockAlertLevel.atencao:
                        projectionBg = const Color(0xFFFFF3E0);
                        projectionBorder = const Color(0xFFFFCC80);
                        projectionText = const Color(0xFFE65100);
                        projectionIcon = Icons.warning_amber_rounded;
                        break;
                      case StockAlertLevel.vencimentoProximo:
                        projectionBg = const Color(0xFFFFF8E1);
                        projectionBorder = const Color(0xFFFFE082);
                        projectionText = const Color(0xFFF57F17);
                        projectionIcon = Icons.access_time;
                        break;
                      case StockAlertLevel.excesso:
                        projectionBg = const Color(0xFFE1F5FE);
                        projectionBorder = const Color(0xFF90CAF9);
                        projectionText = const Color(0xFF0277BD);
                        projectionIcon = Icons.inventory_2_outlined;
                        break;
                      case StockAlertLevel.normal:
                        projectionBg = const Color(0xFFE8F3EB);
                        projectionBorder = const Color(0xFFA5D6A7);
                        projectionText = const Color(0xFF1E5631);
                        projectionIcon = Icons.calendar_today_outlined;
                        break;
                    }

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: projectionBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: projectionBorder, width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(projectionIcon, color: projectionText, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  weeklyUsage > 0
                                      ? 'Projeção: Dura $daysLeft dias'
                                      : 'Projeção: Sem consumo ativo',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: projectionText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 30),
                            child: Text(
                              currentProduct.analyticalRecommendation,
                              style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.monetization_on_outlined, size: 18, color: Color(0xFF1E5631)),
                              SizedBox(width: 6),
                              Text(
                                'Financeiro & Custo',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F3EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              currentProduct.financialHealthLabel,
                              style: const TextStyle(
                                color: Color(0xFF1E5631),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Valor de aquisição',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  CultivaFormat.currency(currentProduct.acquisitionPrice),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text('por ${currentProduct.unit.toLowerCase().replaceAll('sacos', 'saco')}',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Capital em estoque',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                const SizedBox(height: 2),
                                Text(
                                  CultivaFormat.currency(capitalInvested),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text('${currentProduct.currentBalance.toInt()} ${currentProduct.unit.toLowerCase()}',
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              currentProduct.alertLevel == StockAlertLevel.excesso
                                  ? 'Atenção ao excesso: volume elevado estocado além da janela segura de uso da safra.'
                                  : 'Giro regular, sem capital imobilizado excessivo para a safra atual.',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Movimentações',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () => _showAllMovementsHistory(context, currentProduct),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        children: [
                          Text('Ver histórico completo', style: TextStyle(color: Color(0xFF1E5631), fontSize: 12)),
                          Icon(Icons.chevron_right, size: 16, color: Color(0xFF1E5631)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (currentProduct.history.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.history, color: Colors.grey.shade400, size: 30),
                          const SizedBox(height: 6),
                          Text('Nenhuma movimentação registrada',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ),
                    ),
                  )
                else
                  ...currentProduct.history.take(5).map((movement) {
                    final isSaida = movement.type == MovementType.saida;
                    final sign = isSaida ? '-' : '+';
                    final badgeBg = isSaida ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);
                    final badgeText = isSaida ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
                    final typeLabel = isSaida ? 'Saída' : 'Entrada';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: badgeBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isSaida ? Icons.arrow_downward : Icons.arrow_upward,
                              size: 16,
                              color: badgeText,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        typeLabel,
                                        style: TextStyle(
                                          color: badgeText,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        movement.destination.isNotEmpty
                                            ? movement.destination
                                            : (movement.description.isNotEmpty ? movement.description : 'Armazém Central'),
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${CultivaFormat.dateTimeShort(movement.date)}${movement.responsible.isNotEmpty ? ' • ${movement.responsible}' : ''}',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$sign${CultivaFormat.number(movement.quantity)} ${currentProduct.unit}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: badgeText,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _showRegisterMovementSheet(context, currentProduct);
                    },
                    icon: const Icon(Icons.swap_horiz, color: Colors.white),
                    label: const Text(
                      'Registrar Baixa / Movimentação',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E5631),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatOptional(String? val) {
    if (val == null ||
        val.trim().isEmpty ||
        val == 'S/L' ||
        val == 'Fornecedor Direto' ||
        val == 'Fornecedor da NF-e') {
      return 'Não informado';
    }
    return val.trim();
  }

  String _formatValidity(DateTime? date) {
    if (date == null) return 'Não informado';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final valDate = DateTime(date.year, date.month, date.day);
    final days = valDate.difference(today).inDays;
    if (days < 0) {
      return '${CultivaFormat.dateOnly(date)} (Vencido há ${days.abs()}d)';
    } else if (days == 0) {
      return '${CultivaFormat.dateOnly(date)} (Vence hoje!)';
    } else if (days <= 7) {
      return '${CultivaFormat.dateOnly(date)} (Vence em ${days}d - Alerta!)';
    }
    return CultivaFormat.dateOnly(date);
  }

  Widget _buildInfoColumn(String title, String value, {bool isMuted = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isMuted ? FontWeight.normal : FontWeight.w500,
            color: isMuted ? Colors.grey.shade500 : Colors.black87,
            fontStyle: isMuted ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ],
    );
  }

  void _showAllMovementsHistory(BuildContext context, Product p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history, color: Color(0xFF1E5631), size: 22),
                      const SizedBox(width: 8),
                      Text('Movimentações: ${p.name}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const Divider(),
              if (p.history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('Nenhuma movimentação registrada',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                SizedBox(
                  height: 380,
                  child: ListView.builder(
                    itemCount: p.history.length,
                    itemBuilder: (context, i) {
                      final m = p.history[i];
                      final isSaida = m.type == MovementType.saida;
                      final iconColor = isSaida ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
                      final badgeBg = isSaida ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: badgeBg,
                          child: Icon(
                            isSaida ? Icons.arrow_downward : Icons.arrow_upward,
                            color: iconColor,
                            size: 16,
                          ),
                        ),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isSaida ? 'Saída' : 'Entrada',
                                style: TextStyle(
                                  color: iconColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m.destination.isNotEmpty ? m.destination : m.description,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${CultivaFormat.dateTimeShort(m.date)}${m.responsible.isNotEmpty ? ' • ${m.responsible}' : ''}${m.invoiceNumber != null ? ' (NF: ${m.invoiceNumber})' : ''}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                        ),
                        trailing: Text(
                          '${isSaida ? '-' : '+'}${CultivaFormat.number(m.quantity)} ${p.unit}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: iconColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showRegisterMovementSheet(BuildContext context, Product p) {
    final qtyController = TextEditingController();
    final destController = TextEditingController(text: 'Plantio • Talhão 01');
    final respController = TextEditingController(text: 'Operador de Campo');
    final descController = TextEditingController(text: 'Aplicação operacional');
    MovementType selectedType = MovementType.saida;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Movimentar ${p.name}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Saída / Baixa')),
                          selected: selectedType == MovementType.saida,
                          selectedColor: const Color(0xFF1E5631),
                          labelStyle: TextStyle(
                            color: selectedType == MovementType.saida ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedType = MovementType.saida);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Entrada')),
                          selected: selectedType == MovementType.entrada,
                          selectedColor: const Color(0xFF1E5631),
                          labelStyle: TextStyle(
                            color: selectedType == MovementType.entrada ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedType = MovementType.entrada);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantidade (${p.unit})',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destController,
                    decoration: InputDecoration(
                      labelText: selectedType == MovementType.saida ? 'Destino (Talhão / Trator)' : 'Origem / Fornecedor',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: respController,
                    decoration: InputDecoration(
                      labelText: 'Responsável',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: 'Observação / Descrição',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E5631),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        final qty = double.tryParse(qtyController.text) ?? 0;
                        if (qty > 0) {
                          if (selectedType == MovementType.saida) {
                            CultivaStockRepository().recordOutflow(
                              productId: p.id,
                              quantity: qty,
                              destination: destController.text,
                              responsible: respController.text,
                              description: descController.text,
                            );
                          } else {
                            CultivaStockRepository().recordInflow(
                              productId: p.id,
                              quantity: qty,
                              supplier: p.supplier,
                              lot: p.lot,
                              responsible: respController.text,
                              description: descController.text,
                            );
                          }
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Movimentação de $qty ${p.unit} realizada! Consumo e saldos recalculados.'),
                              backgroundColor: const Color(0xFF1E5631),
                            ),
                          );
                        }
                      },
                      child: const Text('Confirmar Movimentação', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
