import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cultivastock/main.dart';

void main() {
  testWidgets('CultivaStock smoke test with clean state', (WidgetTester tester) async {
    await tester.pumpWidget(const CultivaStockApp());
    expect(find.text('CULTIVASTOCK'), findsWidgets);
    expect(find.text('Visão operacional do armazém central'), findsOneWidget);
    expect(find.text('0 itens'), findsWidgets);
  });

  test('Dynamic stock status recalculation upon new stock entry', () {
    final repo = CultivaStockRepository();

    // 1. Cadastra produto com saldo inicial baixo (crítico)
    final product = Product(
      id: 'test_prod_1',
      name: 'Adubo NPK 04-14-08',
      description: 'Fertilizante base para plantio',
      category: 'Fertilizantes',
      currentBalance: 2,
      unit: 'Sacos',
      minimumStockDays: 15,
      validity: DateTime.now().add(const Duration(days: 180)),
      lot: 'L-TEST-01',
      supplier: 'AgroFertil',
      acquisitionPrice: 120.0,
      history: [],
      consumptionPeriod: 'Por Semana',
    );

    repo.addProduct(product);

    // Saldo 2 < 7.5 (meta 15 / 2) -> Crítico
    expect(product.alertLevel, equals(StockAlertLevel.critico));
    expect(product.stockStatusLabel, equals('Crítico'));

    // 2. Registra entrada que eleva o saldo para 10 (< meta 15) -> Atenção
    repo.recordInflow(
      productId: product.id,
      quantity: 8,
      supplier: 'AgroFertil',
      lot: 'L-TEST-01',
      responsible: 'Almoxarife',
    );

    expect(product.currentBalance, equals(10.0));
    expect(product.alertLevel, equals(StockAlertLevel.atencao));
    expect(product.stockStatusLabel, equals('Atenção'));

    // 3. Registra entrada que eleva o saldo para 25 (>= meta 15) -> Normal
    repo.recordInflow(
      productId: product.id,
      quantity: 15,
      supplier: 'AgroFertil',
      lot: 'L-TEST-02',
      responsible: 'Almoxarife',
    );

    expect(product.currentBalance, equals(25.0));
    expect(product.alertLevel, equals(StockAlertLevel.normal));
    expect(product.stockStatusLabel, equals('Normal'));

    // 4. Registra consumo/saída de 14 sacos
    // Consumo apurado: 14 sacos na semana = 2 sacos/dia
    // Saldo restante: 11 sacos -> dias estimados: 11 / 2 = 5 dias (<= meta 15) -> Crítico
    repo.recordOutflow(
      productId: product.id,
      quantity: 14,
      destination: 'Talhão 02',
      responsible: 'Tratorista',
      description: 'Aplicação no milho',
    );

    expect(product.currentBalance, equals(11.0));
    expect(product.averageDailyConsumption, greaterThan(0));
    expect(product.alertLevel, equals(StockAlertLevel.critico));
    expect(product.stockStatusLabel, equals('Crítico'));
  });

  test('Simulação Agro: Insumo Soja com saída pontual de 5 sacos calcula consumo mensal real e projeção correta de estoque', () {
    final now = DateTime.now();

    // Cenário relatado pelo usuário:
    // Saldo inicial: 10 sacos. Saída única pontual de 5 sacos.
    final soja = Product(
      id: 'prod_soja_simulacao',
      name: 'Soja',
      description: 'Sementes de Soja',
      category: 'Sementes',
      currentBalance: 5, // 10 inicial - 5 de saída = saldo atual 5
      unit: 'Sacos',
      minimumStockDays: 15,
      validity: now.add(const Duration(days: 180)),
      acquisitionPrice: 200.0,
      consumptionPeriod: 'Por Mês', // Padrão Agro
      history: [
        StockMovement(
          id: 'mov_soja_1',
          date: now,
          quantity: 5, // Saída pontual de 5 sacos no mês vigente
          type: MovementType.saida,
          destination: 'Talhão 01',
          responsible: 'Agrônomo',
          description: 'Plantio talhão norte',
        ),
      ],
    );

    // 1. Média de uso mensal não é inflada por projeção semanal (deve ser 5.0 sacos/mês e NÃO 21.4)
    expect(soja.averageMonthlyConsumption, equals(5.0));
    expect(soja.averageConsumption, equals(5.0));
    expect(soja.consumptionPeriodLabel, equals('/mês'));

    // 2. Equivalências proporcionais calculadas a partir da média mensal:
    // Diária: 5 / 30 ≈ 0.1667 sacos/dia
    expect(soja.averageDailyConsumption, closeTo(5.0 / 30.0, 0.001));
    // Semanal: (5 / 30) * 7 ≈ 1.1667 sacos/sem (5 / 4.28)
    expect(soja.averageWeeklyConsumption, closeTo((5.0 / 30.0) * 7.0, 0.001));

    // Formatações na UI (usando CultivaFormat.rate):
    expect(CultivaFormat.rate(soja.averageDailyConsumption), equals('0.17'));
    expect(CultivaFormat.rate(soja.averageWeeklyConsumption), equals('1.17'));
    expect(CultivaFormat.rate(soja.averageMonthlyConsumption), equals('5.0'));

    // 3. Projeção de duração de estoque: saldo atual 5 sacos / (5/30) = 30 dias (e NÃO 7 dias)
    expect(soja.estimatedDaysRemaining, equals(30));
    expect(soja.stockLevelAlert, equals(StockAlertLevel.normal));
  });

  test('Product calculates average consumption by configured measure (Por Mês, Por Semana, Por Dia)', () {
    final now = DateTime.now();
    final productMonthly = Product(
      id: 'prod_measure_1',
      name: 'Milho Teste Medida',
      description: 'Milho grão',
      category: 'Sementes',
      currentBalance: 100,
      unit: 'Sacos',
      minimumStockDays: 20,
      validity: now.add(const Duration(days: 90)),
      acquisitionPrice: 80.0,
      consumptionPeriod: 'Por Mês',
      history: [
        StockMovement(
          id: 'mov_1',
          date: now.subtract(const Duration(days: 1)),
          quantity: 14, // 14 sacos em 1 dia
          type: MovementType.saida,
          destination: 'Talhão 1',
          responsible: 'Operador',
          description: 'Uso recente',
        ),
      ],
    );

    // Consumo mensal apurado com saídas reais no mês ativo
    expect(productMonthly.averageMonthlyConsumption, equals(14.0));
    expect(productMonthly.averageConsumption, equals(14.0));
    expect(productMonthly.consumptionPeriodLabel, equals('/mês'));
    expect(productMonthly.averageDailyConsumption, closeTo(14.0 / 30.0, 0.001));
    expect(productMonthly.averageWeeklyConsumption, closeTo((14.0 / 30.0) * 7.0, 0.001));
    expect(productMonthly.estimatedDaysRemaining, equals((100 / (14.0 / 30.0)).floor()));

    final productDaily = Product(
      id: 'prod_measure_2',
      name: 'Diesel Teste Medida',
      description: 'Combustível',
      category: 'Combustíveis',
      currentBalance: 500,
      unit: 'Litros',
      minimumStockDays: 10,
      validity: now.add(const Duration(days: 90)),
      acquisitionPrice: 6.0,
      consumptionPeriod: 'Por Dia',
      history: productMonthly.history,
    );

    expect(productDaily.averageConsumption, equals(2.0));
    expect(productDaily.consumptionPeriodLabel, equals('/dia'));

    final productWeekly = Product(
      id: 'prod_measure_3',
      name: 'Herbicida Medida',
      description: 'Defensivo',
      category: 'Defensivos',
      currentBalance: 50,
      unit: 'Litros',
      minimumStockDays: 10,
      validity: now.add(const Duration(days: 90)),
      acquisitionPrice: 150.0,
      consumptionPeriod: 'Por Semana',
      history: productMonthly.history,
    );

    expect(productWeekly.averageWeeklyConsumption, equals(14.0));
    expect(productWeekly.averageConsumption, equals(14.0));
    expect(productWeekly.consumptionPeriodLabel, equals('/sem'));
    expect(productWeekly.averageDailyConsumption, equals(2.0));
    expect(productWeekly.averageMonthlyConsumption, equals(60.0));
  });

  test('Emits BOTH critical stock alert and expiry alert (<= 30 days) without neglecting stock', () {
    final repo = CultivaStockRepository();

    // Produto com saldo crítico E vencimento em 10 dias (<= 30 dias)
    final criticalAndNearExpiryProduct = Product(
      id: 'prod_dual_alert',
      name: 'Milho FS-500 Dual',
      description: 'Semente de alta produtividade',
      category: 'Sementes',
      currentBalance: 2, // Crítico (< meta 20 / 2)
      unit: 'Sacos',
      minimumStockDays: 20,
      validity: DateTime.now().add(const Duration(days: 10)), // Risco de vencimento (<= 30 dias)
      lot: 'ML-DUAL',
      supplier: 'AgroVale',
      acquisitionPrice: 400.0,
      history: [],
      consumptionPeriod: 'Por Mês',
    );

    repo.addProduct(criticalAndNearExpiryProduct);

    // O status composto deve refletir ambos
    expect(criticalAndNearExpiryProduct.stockLevelAlert, equals(StockAlertLevel.critico));
    expect(criticalAndNearExpiryProduct.hasExpiryRisk, isTrue);
    expect(criticalAndNearExpiryProduct.stockStatusLabel, equals('Crítico • Venc.'));

    // Ambas as notificações devem ser emitidas: estoque crítico E risco de validade
    final stockNotifs = repo.notifications.where(
      (n) => n.priority == StockAlertLevel.critico && n.title.contains('Estoque Crítico: Milho FS-500 Dual'),
    );
    final expiryNotifs = repo.notifications.where(
      (n) => n.priority == StockAlertLevel.vencimentoProximo && n.title.contains('Milho FS-500 Dual'),
    );

    expect(stockNotifs.isNotEmpty, isTrue);
    expect(expiryNotifs.isNotEmpty, isTrue);

    // A recomendação analítica deve conter ambos os alertas
    expect(criticalAndNearExpiryProduct.analyticalRecommendation, contains('ALERTA CONJUNTO:'));
  });

  test('Multi-safra management: creates new safra, switches between them, and persists data', () {
    final repo = CultivaStockRepository();

    expect(repo.currentSafra, equals('Safra 2026'));

    // Adiciona produto na safra atual
    final prod2026 = Product(
      id: 'prod_safra_2026',
      name: 'Adubo Safra 2026',
      description: 'Fertilizante',
      category: 'Fertilizantes',
      currentBalance: 50,
      unit: 'Sacos',
      minimumStockDays: 15,
      validity: DateTime.now().add(const Duration(days: 120)),
      acquisitionPrice: 150.0,
      history: [],
      consumptionPeriod: 'Por Mês',
    );
    repo.addProduct(prod2026);
    expect(repo.products.length, greaterThanOrEqualTo(1));

    // Cria nova Safra 2027
    repo.createNewSafra('Safra 2027');
    expect(repo.currentSafra, equals('Safra 2027'));
    expect(repo.products.isEmpty, isTrue); // Armazém novo para a Safra 2027

    // Retorna para a Safra 2026
    repo.selectSafra('Safra 2026');
    expect(repo.currentSafra, equals('Safra 2026'));
    expect(repo.products.any((p) => p.name == 'Adubo Safra 2026'), isTrue);

    // Renomeia Safra
    repo.renameSafra('Safra 2027', 'Safra 2027/2028');
    expect(repo.safras.contains('Safra 2027/2028'), isTrue);
  });

  testWidgets('AddProductScreen requires mandatory minimum stock days and provides measure selection',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const CultivaStockApp(
        home: AddProductScreen(),
      ),
    );

    // Verifica que a seleção de medida de consumo está presente
    expect(find.text('Medida de Consumo Desejada *'), findsOneWidget);

    // Preenche nome, saldo e preço mas deixa meta de estoque mínimo vazia
    await tester.enterText(find.byType(TextFormField).at(0), 'Adubo Potássio');
    await tester.enterText(find.byType(TextFormField).at(1), '50');
    await tester.enterText(find.byType(TextFormField).at(2), '80.0');
    // Campo de meta de estoque mínimo inicia vazio (não tem estático 15)
    await tester.enterText(find.byType(TextFormField).at(3), '');

    // Clica em Salvar
    final saveButton = find.text('Salvar e Adicionar ao Armazém');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // Deve acusar erro de meta de estoque mínimo obrigatória
    expect(find.text('Informe a meta de estoque mínimo em dias *'), findsOneWidget);
  });

  testWidgets('SmartScannerScreen blocks confirmation when minimumStockDays is missing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const CultivaStockApp(
        home: SmartScannerScreen(),
      ),
    );

    // Os itens mockados iniciam com meta pendente
    expect(find.textContaining('Meta estoque mín. pendente *'), findsWidgets);

    // Tenta confirmar a entrada de todos os itens
    final confirmButton = find.text('Confirmar e Adicionar Tudo');
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    // Deve abrir o diálogo de preenchimento obrigatório e bloquear o salvamento
    expect(find.text('Preenchimento Obrigatório'), findsOneWidget);
    expect(find.textContaining('Meta de Estoque Mínimo'), findsWidgets);

    // Fecha o diálogo de aviso
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    // Abre o diálogo de edição do primeiro item
    final editButtons = find.byIcon(Icons.edit_outlined);
    await tester.tap(editButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('Editar Item do Scanner'), findsOneWidget);
    expect(find.text('Meta de Estoque Mínimo (dias) * (Obrigatória)'), findsOneWidget);
    expect(find.text('Medida de Consumo Desejada *'), findsOneWidget);

    // Cancela o diálogo
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
}
