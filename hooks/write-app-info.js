/*
 * before_prepare hook, shared by every project in this workspace.
 * Writes platforms/android/platform_www/app-info.js describing which
 * project/variant produced this build, so the shared www/index.html can
 * display it at runtime. Must run *before* cordova-android's own prepare
 * step, which merges platform_www + the shared repo-root www/ into
 * app/src/main/assets/www in the same prepare cycle (an after_prepare hook
 * would write this file one prepare cycle too late to be picked up).
 * It doesn't touch the shared repo-root www/ folder.
 */

const fs = require('fs');
const path = require('path');

module.exports = function (context) {
    const projectRoot = context.opts.projectRoot;

    const outDir = path.join(projectRoot, 'platforms', 'android', 'platform_www');
    if (!fs.existsSync(outDir)) {
        return;
    }

    const ConfigParser = require(path.join(projectRoot, 'node_modules', 'cordova-common')).ConfigParser;
    const config = new ConfigParser(path.join(projectRoot, 'config.xml'));

    const pkg = JSON.parse(fs.readFileSync(path.join(projectRoot, 'package.json'), 'utf8'));
    const devDependencies = pkg.devDependencies || {};

    let cordovaAndroidVersion = 'unknown';
    try {
        const platformPkg = JSON.parse(
            fs.readFileSync(path.join(projectRoot, 'node_modules', 'cordova-android', 'package.json'), 'utf8')
        );
        cordovaAndroidVersion = platformPkg.version;
    } catch (e) {
        // cordova-android not installed yet
    }

    const extraPlugins = Object.keys(devDependencies).filter(
        (name) => name !== 'cordova' && name !== 'cordova-android'
    );

    const info = {
        projectDir: path.basename(projectRoot),
        appId: config.packageName(),
        appName: config.name(),
        cordovaAndroidEngineRange: devDependencies['cordova-android'] || 'unknown',
        cordovaAndroidVersion,
        androidEdgeToEdge: config.getPreference('AndroidEdgeToEdge', 'android') || 'n/a',
        extraPlugins
    };

    fs.writeFileSync(path.join(outDir, 'app-info.js'), 'window.APP_INFO = ' + JSON.stringify(info, null, 2) + ';\n');
};
