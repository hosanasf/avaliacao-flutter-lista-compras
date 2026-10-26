import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ListaComprasApp());
}

class Produto {
  final int? id;
  final String nome;
  final int quantidade;
  final double preco;
  final String cloudId;

  const Produto({
    this.id,
    required this.nome,
    required this.quantidade,
    required this.preco,
    this.cloudId = '',
  });

  double get total => quantidade * preco;

  Map<String, Object?> toMap() => {
        'id': id,
        'nome': nome,
        'quantidade': quantidade,
        'preco': preco,
        'cloudId': cloudId,
      };

  factory Produto.fromMap(Map<String, Object?> map) => Produto(
        id: map['id'] as int?,
        nome: map['nome'] as String,
        quantidade: map['quantidade'] as int,
        preco: (map['preco'] as num).toDouble(),
        cloudId: (map['cloudId'] as String?) ?? '',
      );

  Map<String, dynamic> toCloudMap() => {
        'nome': nome,
        'quantidade': quantidade,
        'preco': preco,
        'atualizadoEm': FieldValue.serverTimestamp(),
      };

  factory Produto.fromCloud(
      String documentId, Map<String, dynamic> map) {
    return Produto(
      nome: map['nome'] as String? ?? '',
      quantidade: (map['quantidade'] as num?)?.toInt() ?? 1,
      preco: (map['preco'] as num?)?.toDouble() ?? 0,
      cloudId: documentId,
    );
  }
}

class BancoLocal {
  BancoLocal._();
  static final BancoLocal instance = BancoLocal._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'lista_compras.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE produtos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            quantidade INTEGER NOT NULL,
            preco REAL NOT NULL,
            cloudId TEXT NOT NULL DEFAULT ''
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Produto>> listar() async {
    final db = await database;
    final rows = await db.query('produtos', orderBy: 'id DESC');
    return rows.map(Produto.fromMap).toList();
  }

  Future<int> inserir(Produto produto) async {
    final db = await database;
    return db.insert('produtos', produto.toMap()..remove('id'));
  }

  Future<void> atualizar(Produto produto) async {
    final db = await database;
    await db.update('produtos', produto.toMap(),
        where: 'id = ?', whereArgs: [produto.id]);
  }

  Future<void> excluir(int id) async {
    final db = await database;
    await db.delete('produtos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> substituirTodos(List<Produto> produtos) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('produtos');
      for (final produto in produtos) {
        await txn.insert('produtos', produto.toMap()..remove('id'));
      }
    });
  }
}

class Nuvem {
  final CollectionReference<Map<String, dynamic>> _colecao =
      FirebaseFirestore.instance.collection('produtos');

  Future<String> salvar(Produto produto) async {
    if (produto.cloudId.isNotEmpty) {
      await _colecao.doc(produto.cloudId).set(produto.toCloudMap());
      return produto.cloudId;
    }
    final doc = await _colecao.add(produto.toCloudMap());
    return doc.id;
  }

  Future<void> excluir(String cloudId) async {
    if (cloudId.isNotEmpty) await _colecao.doc(cloudId).delete();
  }

  Future<List<Produto>> listar() async {
    final snapshot = await _colecao.get();
    return snapshot.docs
        .map((doc) => Produto.fromCloud(doc.id, doc.data()))
        .toList();
  }
}

class ListaComprasApp extends StatelessWidget {
  const ListaComprasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minha Lista de Compras',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16877D)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F8F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16877D),
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      home: const TelaPrincipal(),
    );
  }
}

class TelaPrincipal extends StatefulWidget {
  const TelaPrincipal({super.key});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  List<Produto> produtos = [];
  bool carregando = true;
  bool nuvemDisponivel = true;
  String mensagem = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      carregando = true;
      mensagem = '';
    });
    try {
      // Mantém os dados locais disponíveis e tenta atualizar pela nuvem.
      final locais = await BancoLocal.instance.listar();
      List<Produto> lista = locais;
      try {
        final remotos = await Nuvem().listar();
        // Mantém itens criados localmente que ainda não foram enviados à nuvem.
        final locaisPendentes = locais.where((item) => item.cloudId.isEmpty);
        await BancoLocal.instance.substituirTodos([...remotos, ...locaisPendentes]);
        lista = await BancoLocal.instance.listar();
        nuvemDisponivel = true;
      } catch (_) {
        nuvemDisponivel = false;
        mensagem = 'Sem conexão com a nuvem. Exibindo dados locais.';
      }
      if (!mounted) return;
      setState(() {
        produtos = lista;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        carregando = false;
        mensagem = 'Não foi possível carregar os produtos: $e';
      });
    }
  }

  Future<void> _abrirFormulario({Produto? produto}) async {
    final resultado = await Navigator.push<Produto>(
      context,
      MaterialPageRoute(
        builder: (_) => TelaFormulario(produto: produto),
      ),
    );
    if (resultado == null) return;

    try {
      if (produto == null) {
        final id = await BancoLocal.instance.inserir(resultado);
        final salvo = Produto(
          id: id,
          nome: resultado.nome,
          quantidade: resultado.quantidade,
          preco: resultado.preco,
        );
        try {
          final cloudId = await Nuvem().salvar(salvo);
          await BancoLocal.instance.atualizar(Produto(
            id: id,
            nome: salvo.nome,
            quantidade: salvo.quantidade,
            preco: salvo.preco,
            cloudId: cloudId,
          ));
        } catch (_) {
          nuvemDisponivel = false;
        }
      } else {
        final editado = Produto(
          id: produto.id,
          nome: resultado.nome,
          quantidade: resultado.quantidade,
          preco: resultado.preco,
          cloudId: produto.cloudId,
        );
        await BancoLocal.instance.atualizar(editado);
        try {
          final cloudId = await Nuvem().salvar(editado);
          await BancoLocal.instance.atualizar(Produto(
            id: editado.id,
            nome: editado.nome,
            quantidade: editado.quantidade,
            preco: editado.preco,
            cloudId: cloudId,
          ));
          nuvemDisponivel = true;
        } catch (_) {
          nuvemDisponivel = false;
        }
      }
      await _carregar();
    } catch (e) {
      _avisar('Erro ao salvar: $e');
    }
  }

  Future<void> _excluir(Produto produto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir produto?'),
        content: Text('Deseja excluir "${produto.nome}" da lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || produto.id == null) return;
    await BancoLocal.instance.excluir(produto.id!);
    try {
      await Nuvem().excluir(produto.cloudId);
    } catch (_) {
      nuvemDisponivel = false;
    }
    await _carregar();
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  String _dinheiro(double valor) => 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    final total = produtos.fold<double>(0, (soma, p) => soma + p.total);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Minha Lista'),
            Text('Organize suas compras', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            onPressed: _carregar,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFFE0F2EF),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Valor estimado da lista'),
                    const SizedBox(height: 6),
                    Text(_dinheiro(total),
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${produtos.length} produto(s) cadastrado(s)'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          nuvemDisponivel ? Icons.cloud_done : Icons.cloud_off,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            nuvemDisponivel
                                ? 'Conexão com a nuvem disponível'
                                : 'Nuvem indisponível; verifique a conexão',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (mensagem.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(mensagem, style: const TextStyle(color: Colors.orange)),
              ),
            const SizedBox(height: 12),
            const Text('Seus produtos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (carregando)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (produtos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Column(
                  children: [
                    Icon(Icons.shopping_basket_outlined, size: 54, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Sua lista está vazia.'),
                    Text('Toque em “Adicionar” para começar.'),
                  ],
                ),
              )
            else
              ...produtos.map((produto) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE0F2EF),
                        child: Text('${produto.quantidade}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: Text(produto.nome,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${produto.quantidade} un. × ${_dinheiro(produto.preco)}\nTotal: ${_dinheiro(produto.total)}',
                      ),
                      isThreeLine: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TelaDetalhes(
                            produto: produto,
                            aoEditar: () => _abrirFormulario(produto: produto),
                            aoExcluir: () => _excluir(produto),
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  )),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class TelaFormulario extends StatefulWidget {
  final Produto? produto;
  const TelaFormulario({super.key, this.produto});

  @override
  State<TelaFormulario> createState() => _TelaFormularioState();
}

class _TelaFormularioState extends State<TelaFormulario> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _quantidade;
  late final TextEditingController _preco;

  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.produto?.nome ?? '');
    _quantidade = TextEditingController(
        text: widget.produto?.quantidade.toString() ?? '1');
    _preco = TextEditingController(
        text: widget.produto?.preco.toString().replaceAll('.', ',') ?? '');
  }

  @override
  void dispose() {
    _nome.dispose();
    _quantidade.dispose();
    _preco.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_formKey.currentState!.validate()) return;
    final preco = double.parse(_preco.text.trim().replaceAll(',', '.'));
    Navigator.pop(
      context,
      Produto(
        nome: _nome.text.trim(),
        quantidade: int.parse(_quantidade.text.trim()),
        preco: preco,
        cloudId: widget.produto?.cloudId ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.produto == null ? 'Novo produto' : 'Editar produto'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 64, color: Color(0xFF16877D)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(
                labelText: 'Nome do produto',
                hintText: 'Ex.: Maçã',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.shopping_basket_outlined),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Informe o nome.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantidade,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 ? 'Informe uma quantidade válida.' : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _preco,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço unitário (R\$)',
                hintText: 'Ex.: 4,50',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                return n == null || n < 0 ? 'Informe um preço válido.' : null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar produto'),
            ),
          ],
        ),
      ),
    );
  }
}

class TelaDetalhes extends StatelessWidget {
  final Produto produto;
  final VoidCallback aoEditar;
  final VoidCallback aoExcluir;

  const TelaDetalhes({
    super.key,
    required this.produto,
    required this.aoEditar,
    required this.aoExcluir,
  });

  String dinheiro(double valor) =>
      'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do produto')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 42,
            child: Icon(Icons.shopping_bag_outlined, size: 42),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(produto.nome,
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          _linha('Nome', produto.nome),
          _linha('Quantidade', '${produto.quantidade} unidade(s)'),
          _linha('Preço unitário', dinheiro(produto.preco)),
          _linha('Preço total', dinheiro(produto.total)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              aoEditar();
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar produto'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              aoExcluir();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir produto'),
          ),
        ],
      ),
    );
  }

  Widget _linha(String titulo, String valor) => Card(
        child: ListTile(
          title: Text(titulo, style: const TextStyle(fontSize: 12)),
          subtitle: Text(valor,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
        ),
      );
}
