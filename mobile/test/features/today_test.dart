import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/features/plans/data/plans_repository.dart';
import 'package:index_app/features/tasks/data/tasks_repository.dart';

import '../support.dart';

void main() {
  test('Today merges and orders tasks like the server', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final tasks = TasksRepository(db, onChanged: () {});
    final plans = PlansRepository(db, onChanged: () {});

    final planId = await plans.createPlan(title: 'Go');
    await plans.addMilestone(planId, 'Basics');
    final ms = await db.select(db.milestones).getSingle();

    await tasks.addTask(title: 'Buy milk', scheduledDate: '2026-02-10');
    await tasks.addTask(title: 'Read spec', scheduledDate: '2026-02-10', milestoneId: ms.id);
    await tasks.addTask(title: 'Call mom', scheduledDate: '2026-02-08');
    final gym = await tasks.addTask(title: 'Gym', scheduledDate: '2026-02-10');
    await tasks.toggleCompleted((await tasks.getTask(gym))!);
    await tasks.addTask(title: 'Future', scheduledDate: '2026-02-11');
    await tasks.addTask(title: 'Someday');

    final today = await tasks.watchToday('2026-02-10').first;
    expect(today.map((e) => e.task.title), ['Call mom', 'Read spec', 'Buy milk', 'Gym']);
    expect(today.first.isOverdue, isTrue);
    expect(today[1].planTitle, 'Go');

    // Archived plans drop out of Today.
    await plans.updatePlan((await db.select(db.learningPlans).getSingle()), status: 'archived');
    final after = await tasks.watchToday('2026-02-10').first;
    expect(after.map((e) => e.task.title), isNot(contains('Read spec')));
  });
}
