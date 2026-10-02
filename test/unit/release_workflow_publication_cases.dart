import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void registerReleaseWorkflowPublicationCases() {
  test('triggers the stable landing deployment only after public assets', () {
    final workflow = File('.github/workflows/release-cut.yml')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final publishStart = workflow.indexOf('  publish:');
    final landingStart = workflow.indexOf('  deploy_landing:');
    final packagesStart = workflow.indexOf('  publish_packages:');
    final publish = workflow.substring(publishStart, landingStart);
    final landing = workflow.substring(landingStart, packagesStart);
    final r2 = publish.substring(
      publish.indexOf('      - name: Publish update archive to R2'),
      publish.indexOf('      - name: Cleanup old R2 desktop updates'),
    );
    final helper = File('tool/release/trigger_vercel_deploy_hook.sh')
        .readAsStringSync();

    expect(r2, contains('id: publish_update_archive_r2'));
    expect(
      publish.indexOf('      - name: Publish desktop release'),
      lessThan(publish.indexOf('      - name: Publish update archive to R2')),
    );
    expect(
      publish.indexOf('      - name: Publish mobile release'),
      lessThan(publish.indexOf('      - name: Publish update archive to R2')),
    );
    expect(publish, contains('desktop_assets_public:'));
    expect(publish, contains('mobile_assets_public:'));
    expect(publish, contains('landing_assets_ready:'));
    expect(landing, contains("needs.plan.outputs.channel == 'stable'"));
    expect(landing, contains('always()'));
    expect(landing, contains("needs.publish.result != 'cancelled'"));
    expect(
      landing,
      contains("needs.plan.outputs.any_should_release == 'true'"),
    );
    expect(
      landing,
      contains("needs.publish.outputs.landing_assets_ready == 'true'"),
    );
    expect(landing, contains('needs:\n      - plan\n      - publish'));
    expect(landing, contains('VERCEL_PRODUCTION_DEPLOY_HOOK'));
    expect(landing, contains('trigger_vercel_deploy_hook.sh'));
    expect(helper, contains('required for stable release publication'));
    expect(helper, contains('Skipping the production landing deployment'));
    expect(helper, contains(r'--config "$config_file"'));
    expect(helper, isNot(contains(r'"$VERCEL_PRODUCTION_DEPLOY_HOOK")')));
    expect(helper, isNot(contains(r'echo "$VERCEL_PRODUCTION_DEPLOY_HOOK"')));
    expect(publish, isNot(contains('trigger_vercel_deploy_hook.sh')));
    expect(landing, isNot(contains("needs.publish.result == 'success'")));
    expect(landingStart, lessThan(packagesStart));
    expect(landing, contains('timeout-minutes: 5'));
  });

  test('publishes desktop packages when the mobile build is skipped', () {
    final workflow = File('.github/workflows/release-cut.yml')
        .readAsStringSync();
    final packageJob = workflow.substring(
      workflow.indexOf('  publish_packages:'),
      workflow.indexOf('  publish_chocolatey:'),
    );
    final chocolateyJob = workflow.substring(
      workflow.indexOf('  publish_chocolatey:'),
    );

    expect(packageJob, contains('always()'));
    expect(packageJob, contains('!cancelled()'));
    expect(packageJob, contains("needs.plan.result == 'success'"));
    expect(packageJob, contains("needs.publish.result != 'cancelled'"));
    expect(
      packageJob,
      contains("needs.publish.outputs.desktop_assets_public == 'true'"),
    );
    expect(packageJob, isNot(contains("needs.publish.result == 'success'")));
    expect(chocolateyJob, contains('!cancelled()'));
    expect(
      chocolateyJob,
      contains("needs.publish_packages.result == 'success'"),
    );
  });

  test(
    'keeps package publication eligible after post-publish cleanup failure',
    () {
      final workflow = File('.github/workflows/release-cut.yml')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final publish = workflow.substring(
        workflow.indexOf('  publish:'),
        workflow.indexOf('  deploy_landing:'),
      );
      final packageJob = workflow.substring(
        workflow.indexOf('  publish_packages:'),
        workflow.indexOf('  publish_chocolatey:'),
      );

      expect(publish, contains('desktop_assets_public:'));
      expect(publish, contains('steps.publish_update_archive_r2.outcome'));
      expect(packageJob, contains('always()'));
      expect(packageJob, contains("needs.publish.result != 'cancelled'"));
      expect(
        packageJob,
        contains("needs.publish.outputs.desktop_assets_public == 'true'"),
      );
      expect(packageJob, isNot(contains("needs.publish.result == 'success'")));
    },
  );

  test('publishes only after the prepared version pull request merges', () {
    final workflow = File('.github/workflows/release-cut.yml')
        .readAsStringSync();
    final publish = workflow.substring(workflow.indexOf('  publish:'));

    expect(workflow, contains('pull_request:'));
    expect(workflow, contains('- closed'));
    expect(workflow, contains('prepare_version_pr:'));
    expect(workflow, contains('prepared_release.dart write'));
    expect(workflow, contains('prepared_release.dart inspect'));
    expect(workflow, contains('--state open'));
    expect(workflow, contains('--force-with-lease='));
    expect(
      workflow,
      isNot(contains('closed, merged, or has an unexpected head')),
    );
    expect(workflow, contains("ready_to_publish == 'true'"));
    expect(workflow, contains('gh workflow run pr.yml'));
    expect(workflow, contains('gh workflow run landing.yml'));
    expect(workflow, isNot(contains('HEAD:refs/heads/main')));
    expect(
      workflow,
      isNot(contains('--force-with-lease origin HEAD~1:refs/heads/main')),
    );
    expect(publish, contains('ref: \${{ needs.plan.outputs.target_sha }}'));
    expect(publish, contains('--verify-tag'));
  });

  test('dispatches exact-head checks for automation-created pull requests', () {
    final pr = File('.github/workflows/pr.yml').readAsStringSync();
    final release = File('.github/workflows/release-cut.yml')
        .readAsStringSync();

    expect(pr, contains('workflow_dispatch:'));
    expect(pr, contains('base_sha:'));
    expect(pr, contains('head_sha:'));
    expect(pr, contains(r'git diff --check "$BASE_SHA...$HEAD_SHA"'));
    expect(File('.mergify.yml').existsSync(), isFalse);
    expect(File('.github/workflows/merge-queue.yml').existsSync(), isFalse);
    expect(release, isNot(contains('Mergify')));
    expect(release, contains('Squash-merge this pull request after'));
  });
}
