#include <QGuiApplication>
#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTemporaryDir>
#include <QtTest>
#include <memory>

class ClipboardPreviewTests : public QObject {
    Q_OBJECT
private slots:
    void largeImageIsBoundedAndReleased_data() {
        QTest::addColumn<double>("scale");
        QTest::addColumn<QSize>("originalSize");
        QTest::addColumn<QString>("extension");
        for (double scale : {1.0, 1.5, 2.0}) {
            const auto name = QByteArray::number(scale);
            QTest::newRow((name + "-landscape-jpeg").constData()) << scale << QSize(3840, 2160) << QString("jpg");
            QTest::newRow((name + "-portrait-jpeg").constData()) << scale << QSize(2160, 3840) << QString("jpg");
            QTest::newRow((name + "-landscape-png").constData()) << scale << QSize(3840, 2160) << QString("png");
        }
    }

    void largeImageIsBoundedAndReleased() {
        QFETCH(double, scale);
        QFETCH(QSize, originalSize);
        QFETCH(QString, extension);
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString path = directory.filePath("4k." + extension);
        QImage fixture(originalSize, QImage::Format_RGB32);
        fixture.fill(Qt::blue);
        QVERIFY(fixture.save(path));
        fixture = {};

        QQmlEngine engine;
        QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(CLIPBOARD_PREVIEW_SOURCE)));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> image(component.create());
        QVERIFY(image);
        auto *item = qobject_cast<QQuickItem *>(image.get());
        QVERIFY(item);
        item->setWidth(496);
        item->setHeight(300);
        QVERIFY(image->setProperty("devicePixelRatio", scale));
        QVERIFY(image->setProperty("imagePath", path));
        // A selected image does not decode until full preview is opened.
        QCOMPARE(image->property("source").toUrl(), QUrl());
        QCOMPARE(image->property("status").toInt(), 0); // Image.Null

        QVERIFY(image->setProperty("previewActive", true));
        QTRY_COMPARE_WITH_TIMEOUT(image->property("status").toInt(), 1, 3000); // Image.Ready
        const auto decoded = image->property("sourceSize").toSize();
        QVERIFY(decoded.width() > 0 && decoded.height() > 0);
        QVERIFY(decoded.width() <= qCeil(520 * scale));
        QVERIFY(decoded.height() <= qCeil(400 * scale));
        const auto implicitSize = QSizeF(item->implicitWidth(), item->implicitHeight());
        QVERIFY2(qRound(implicitSize.width()) <= qCeil(520 * scale),
                 qPrintable(QString::number(implicitSize.width(), 'g', 17)));
        QVERIFY2(qRound(implicitSize.height()) <= qCeil(400 * scale),
                 qPrintable(QString::number(implicitSize.height(), 'g', 17)));
        QVERIFY(qAbs(implicitSize.width() / implicitSize.height()
                     - double(originalSize.width()) / originalSize.height()) < 0.02);

        // Capsule animation must not trigger repeated image decoding.
        QSignalSpy sizeChanges(image.get(), SIGNAL(sourceSizeChanged()));
        QSignalSpy statusChanges(image.get(), SIGNAL(statusChanged()));
        QVERIFY(sizeChanges.isValid());
        QVERIFY(statusChanges.isValid());
        QVERIFY(!item->childItems().isEmpty());
        auto *display = item->childItems().first();
        for (int width = 100; width <= 500; width += 20) {
            item->setWidth(width);
            item->setHeight(width / 2.0);
            QVERIFY(display->width() <= item->width() + 0.01);
            QVERIFY(display->height() <= item->height() + 0.01);
            QVERIFY(qAbs(display->width() / display->height()
                         - double(originalSize.width()) / originalSize.height()) < 0.02);
        }
        QCOMPARE(sizeChanges.count(), 0);
        QCOMPARE(statusChanges.count(), 0);
        QCOMPARE(image->property("status").toInt(), 1);

        QVERIFY(image->setProperty("previewActive", false));
        QCOMPARE(image->property("source").toUrl(), QUrl());
        QTRY_COMPARE(image->property("status").toInt(), 0);
        QTRY_VERIFY(qFuzzyIsNull(item->implicitWidth()) && qFuzzyIsNull(item->implicitHeight()));
    }
};

QTEST_MAIN(ClipboardPreviewTests)
#include "clipboard_preview_tests.moc"
