// Headless check of the plasma-nm OpenVPN plugin PKCS#11 UI.
// Built and run by tests/plasma-nm-openvpn-ui.sh inside the Fedora rootfs.
#include <QApplication>
#include <QComboBox>
#include <QPluginLoader>
#include <QPushButton>
#include <QTest>

#include <KPluginFactory>
#include <NetworkManagerQt/VpnSetting>

#include "passwordfield.h"
#include "vpnuiplugin.h"

static int failures = 0;
#define CHECK(cond)                                                                                                                                            \
    do {                                                                                                                                                       \
        if (!(cond)) {                                                                                                                                         \
            qWarning("FAIL %s:%d: %s", __FILE__, __LINE__, #cond);                                                                                             \
            failures++;                                                                                                                                        \
        } else {                                                                                                                                               \
            qInfo("ok   %s", #cond);                                                                                                                           \
        }                                                                                                                                                      \
    } while (0)

static NetworkManager::VpnSetting::Ptr makeSetting(const NMStringMap &data, const NMStringMap &secrets = {})
{
    NetworkManager::VpnSetting::Ptr s(new NetworkManager::VpnSetting);
    s->setServiceType(QStringLiteral("org.freedesktop.NetworkManager.openvpn"));
    s->setData(data);
    s->setSecrets(secrets);
    return s;
}

static NMStringMap dataOf(SettingWidget *w)
{
    NetworkManager::VpnSetting out;
    out.fromMap(w->setting());
    return out.data();
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QString pluginPath = QString::fromLocal8Bit(qgetenv("PLUGIN"));
    const QString pkcs11Id = QString::fromLocal8Bit(qgetenv("PKCS11_ID"));

    auto result = KPluginFactory::instantiatePlugin<VpnUiPlugin>(KPluginMetaData(pluginPath));
    if (!result) {
        qFatal("cannot load %s: %s", qPrintable(pluginPath), qPrintable(result.errorText));
    }
    VpnUiPlugin *plugin = result.plugin;

    // 1. round trip of a PKCS#11 connection
    {
        const NMStringMap data{{QStringLiteral("connection-type"), QStringLiteral("pkcs11")},
                               {QStringLiteral("remote"), QStringLiteral("vpn.example.com")},
                               {QStringLiteral("ca"), QStringLiteral("/etc/ca.crt")},
                               {QStringLiteral("pkcs11-id"), QStringLiteral("pkcs11:token=foo;id=%01")},
                               {QStringLiteral("cert-pass-flags"), QStringLiteral("2")}};
        auto setting = makeSetting(data);
        SettingWidget *w = plugin->widget(setting, nullptr);
        w->loadConfig(setting); // what the connection editor does
        auto type = w->findChild<QComboBox *>(QStringLiteral("cmbConnectionType"));
        CHECK(type && type->currentIndex() == 4);
        CHECK(w->isValid());
        const NMStringMap out = dataOf(w);
        CHECK(out.value(QStringLiteral("connection-type")) == QLatin1String("pkcs11"));
        CHECK(out.value(QStringLiteral("pkcs11-id")) == QLatin1String("pkcs11:token=foo;id=%01"));
        CHECK(out.value(QStringLiteral("ca")) == QLatin1String("/etc/ca.crt"));
        CHECK(out.value(QStringLiteral("cert-pass-flags")) == QLatin1String("2"));
        CHECK(!out.contains(QStringLiteral("cert")) && !out.contains(QStringLiteral("key")));

        // empty ID is invalid
        w->findChild<QComboBox *>(QStringLiteral("pkcs11Id"))->setEditText(QString());
        CHECK(!w->isValid());
        delete w;
    }

    // 2. new connection: switch to PKCS#11 and detect certificates on the token
    if (!pkcs11Id.isEmpty()) {
        SettingWidget *w = plugin->widget(makeSetting({{QStringLiteral("remote"), QStringLiteral("gw")}}), nullptr);
        w->findChild<QComboBox *>(QStringLiteral("cmbConnectionType"))->setCurrentIndex(4);
        auto ids = w->findChild<QComboBox *>(QStringLiteral("pkcs11Id"));
        auto detect = w->findChild<QPushButton *>(QStringLiteral("btnPkcs11Detect"));
        detect->click();
        CHECK(QTest::qWaitFor([&] { return detect->isEnabled(); }, 20000));
        CHECK(ids->count() == 1);
        qInfo("     detected: '%s' -> %s", qPrintable(ids->itemText(0)), qPrintable(ids->itemData(0).toString()));
        CHECK(ids->itemData(0).toString() == pkcs11Id);
        const NMStringMap out = dataOf(w);
        CHECK(out.value(QStringLiteral("pkcs11-id")) == pkcs11Id);
        CHECK(out.value(QStringLiteral("connection-type")) == QLatin1String("pkcs11"));
        // default: ask for the PIN every time (NotSaved)
        CHECK(out.value(QStringLiteral("cert-pass-flags")) == QLatin1String("2"));
        delete w;
    }

    // 3. PIN prompt without hints (initial connect)
    {
        auto s = makeSetting({{QStringLiteral("connection-type"), QStringLiteral("pkcs11")}, {QStringLiteral("pkcs11-id"), QStringLiteral("x")}});
        SettingWidget *w = plugin->askUser(s, {}, nullptr);
        const auto fields = w->findChildren<PasswordField *>();
        CHECK(fields.size() == 1);
        CHECK(fields.value(0) && fields[0]->property("nm_secrets_key").toString() == QLatin1String("cert-pass"));
        CHECK(fields.value(0) && fields[0]->findChild<QLineEdit *>()->echoMode() == QLineEdit::Password);
        delete w;
    }

    // 4. PIN prompt requested by the service; "token" in the text must not unmask it
    {
        auto s = makeSetting({{QStringLiteral("connection-type"), QStringLiteral("pkcs11")}, {QStringLiteral("pkcs11-id"), QStringLiteral("x")}});
        SettingWidget *w =
            plugin->askUser(s, {QStringLiteral("cert-pass"), QStringLiteral("x-vpn-message:The PIN for token was not accepted.")}, nullptr);
        const auto fields = w->findChildren<PasswordField *>();
        CHECK(fields.size() == 1);
        CHECK(fields.value(0) && fields[0]->findChild<QLineEdit *>()->echoMode() == QLineEdit::Password);
        delete w;
    }

    // 5. unchanged behaviour for plain TLS connections
    {
        auto s = makeSetting({{QStringLiteral("connection-type"), QStringLiteral("tls")}, {QStringLiteral("key"), QStringLiteral("/k.pem")}});
        SettingWidget *w = plugin->widget(s, nullptr);
        w->loadConfig(s);
        CHECK(w->findChild<QComboBox *>(QStringLiteral("cmbConnectionType"))->currentIndex() == 0);
        CHECK(dataOf(w).value(QStringLiteral("connection-type")) == QLatin1String("tls"));
        delete w;
    }

    qInfo("%s: %d failure(s)", failures ? "FAILED" : "PASSED", failures);
    return failures ? 1 : 0;
}
