
import 'package:flutter_test/flutter_test.dart';
import 'package:lista_compras_flutter/main.dart';

void main() {
  testWidgets('O aplicativo inicia', (WidgetTester tester) async {
    await tester.pumpWidget(const ListaComprasApp());

    expect(find.text('Minha Lista'), findsOneWidget);
    expect(find.text('Organize suas compras'), findsOneWidget);
  });
}
