import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/chat_message.dart' as chat_model;
import '../models/rivr_node.dart';
import '../models/telemetry_reading.dart' as tel_model;

part 'app_database.g.dart';

// ── Table definitions ─────────────────────────────────────────────────────

@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  TextColumn get id => text()();
  // 'text' shadows a Table method — use 'body' as the column name.
  TextColumn get body => text()();
  IntColumn get senderNodeId => integer()();
  TextColumn get senderName => text()();
  IntColumn get timestampMs => integer()(); // DateTime.millisecondsSinceEpoch
  IntColumn get origin => integer()();      // MessageOrigin.index
  IntColumn get channelId => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NodeRow')
class Nodes extends Table {
  IntColumn get nodeId => integer()();
  TextColumn get callsign => text()();
  IntColumn get rssiDbm => integer()();
  IntColumn get snrDb => integer()();
  IntColumn get hopCount => integer()();
  IntColumn get linkScore => integer()();
  IntColumn get lossPercent => integer()();
  IntColumn get lastSeenMs => integer()(); // DateTime.millisecondsSinceEpoch
  IntColumn get role => integer()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  TextColumn get alias => text().nullable()();

  @override
  Set<Column> get primaryKey => {nodeId};
}

@DataClassName('TelemetryReadingRow')
class TelemetryReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get srcNodeId => integer()();
  IntColumn get sensorId => integer()();
  IntColumn get valueX100 => integer()();
  IntColumn get unitCode => integer()();
  IntColumn get timestampS => integer()();
  IntColumn get receivedAtMs => integer()(); // DateTime.millisecondsSinceEpoch
}

// ── Database ──────────────────────────────────────────────────────────────

@DriftDatabase(tables: [ChatMessages, Nodes, TelemetryReadings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(nodes, nodes.alias);
      }
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'rivr_companion');
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  static const _maxMessagesPerChannel = 1000;

  Future<List<chat_model.ChatMessage>> getAllMessages() async {
    final rows = await (select(chatMessages)
          ..orderBy([(t) => OrderingTerm(expression: t.timestampMs)]))
        .get();
    return rows.map(_rowToChat).toList();
  }

  Future<void> insertMessage(chat_model.ChatMessage msg) async {
    await into(chatMessages).insertOnConflictUpdate(
      ChatMessagesCompanion.insert(
        id: msg.id,
        body: msg.text,
        senderNodeId: msg.senderNodeId,
        senderName: msg.senderName,
        timestampMs: msg.timestamp.millisecondsSinceEpoch,
        origin: msg.origin.index,
        channelId: msg.channelId,
      ),
    );
    await _pruneMessages(msg.channelId);
  }

  Future<void> _pruneMessages(int channelId) async {
    // Count rows for this channel.
    final countExpr = chatMessages.id.count();
    final query = selectOnly(chatMessages)
      ..addColumns([countExpr])
      ..where(chatMessages.channelId.equals(channelId));
    final count =
        await query.map((r) => r.read(countExpr)!).getSingleOrNull() ?? 0;

    if (count > _maxMessagesPerChannel) {
      final excess = count - _maxMessagesPerChannel;
      final oldest = await (select(chatMessages)
            ..where((t) => t.channelId.equals(channelId))
            ..orderBy([(t) => OrderingTerm(expression: t.timestampMs)])
            ..limit(excess))
          .get();
      final ids = oldest.map((r) => r.id).toList();
      await (delete(chatMessages)..where((t) => t.id.isIn(ids))).go();
    }
  }

  chat_model.ChatMessage _rowToChat(ChatMessageRow row) {
    return chat_model.ChatMessage(
      id: row.id,
      text: row.body,
      senderNodeId: row.senderNodeId,
      senderName: row.senderName,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestampMs),
      origin: chat_model.MessageOrigin.values[row.origin],
      channelId: row.channelId,
    );
  }

  // ── Nodes ─────────────────────────────────────────────────────────────────

  Future<List<RivrNode>> getAllNodes() async {
    final rows = await select(nodes).get();
    return rows.map(_rowToNode).toList();
  }

  Future<void> upsertNode(RivrNode node) async {
    await into(nodes).insertOnConflictUpdate(
      NodesCompanion(
        nodeId: Value(node.nodeId),
        callsign: Value(node.callsign),
        rssiDbm: Value(node.rssiDbm),
        snrDb: Value(node.snrDb),
        hopCount: Value(node.hopCount),
        linkScore: Value(node.linkScore),
        lossPercent: Value(node.lossPercent),
        lastSeenMs: Value(node.lastSeen.millisecondsSinceEpoch),
        role: Value(node.role),
        lat: Value(node.lat),
        lon: Value(node.lon),
        alias: Value(node.alias),
      ),
    );
  }

  Future<void> setNodeAlias(int nodeId, String? alias) async {
    await (update(nodes)..where((t) => t.nodeId.equals(nodeId)))
        .write(NodesCompanion(alias: Value(alias)));
  }

  RivrNode _rowToNode(NodeRow row) {
    return RivrNode(
      nodeId: row.nodeId,
      callsign: row.callsign,
      rssiDbm: row.rssiDbm,
      snrDb: row.snrDb,
      hopCount: row.hopCount,
      linkScore: row.linkScore,
      lossPercent: row.lossPercent,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(row.lastSeenMs),
      role: row.role,
      lat: row.lat,
      lon: row.lon,
      alias: row.alias,
    );
  }

  // ── Telemetry ─────────────────────────────────────────────────────────────

  Future<List<tel_model.TelemetryReading>> getRecentTelemetry({int retentionDays = 7}) async {
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    final rows = await (select(telemetryReadings)
          ..where((t) => t.receivedAtMs.isBiggerOrEqualValue(cutoffMs))
          ..orderBy([(t) => OrderingTerm(expression: t.receivedAtMs)]))
        .get();
    return rows.map(_rowToTelemetry).toList();
  }

  Future<void> insertTelemetry(tel_model.TelemetryReading r) async {
    await into(telemetryReadings).insert(
      TelemetryReadingsCompanion.insert(
        srcNodeId: r.srcNodeId,
        sensorId: r.sensorId,
        valueX100: r.valueX100,
        unitCode: r.unitCode,
        timestampS: r.timestampS,
        receivedAtMs: r.receivedAt.millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> pruneOldTelemetry({int retentionDays = 7}) async {
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    await (delete(telemetryReadings)
          ..where((t) => t.receivedAtMs.isSmallerThanValue(cutoffMs)))
        .go();
  }

  Future<void> deleteNodeTelemetry(int nodeId) async {
    await (delete(telemetryReadings)
          ..where((t) => t.srcNodeId.equals(nodeId)))
        .go();
  }

  tel_model.TelemetryReading _rowToTelemetry(TelemetryReadingRow row) {
    return tel_model.TelemetryReading(
      srcNodeId: row.srcNodeId,
      sensorId: row.sensorId,
      valueX100: row.valueX100,
      unitCode: row.unitCode,
      timestampS: row.timestampS,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(row.receivedAtMs),
    );
  }
}
