/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import UIKit
import Deferred
import Storage
import WebImage
import XCGLogger

private let log = Logger.browserLogger

// MARK: -  Lifecycle
struct ASPanelUX {
    static let backgroundColor = UIColor(white: 1.0, alpha: 0.5)
    static let topSitesCacheSize = 20
    static let historySize = 10
    static let TopSiteSingleRowHeight: CGFloat = 120
    static let TopSiteDoubleRowHeight: CGFloat = 220
}

class ActivityStreamPanel: UIViewController {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    private let profile: Profile

    lazy private var tableView: UITableView = {
        let tableView = UITableView(frame: CGRect.zero, style: .Grouped)
        tableView.registerClass(SimpleHighlightCell.self, forCellReuseIdentifier: "Cell")
        tableView.registerClass(ASHorizontalScrollCell.self, forCellReuseIdentifier: "TopSite")
        tableView.registerClass(HighlightCell.self, forCellReuseIdentifier: "Highlight")
        tableView.backgroundColor = ASPanelUX.backgroundColor
        tableView.separatorStyle = .None
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.separatorInset = UIEdgeInsetsZero
        tableView.estimatedRowHeight = 65
        tableView.estimatedSectionHeaderHeight = 15
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension
        return tableView
    }()

    private let topSiteHandler = ASHorizontalScrollSource()

    var topSites: [TopSiteItem] = []
    var history: [Site] = []

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)

        self.profile.history.setTopSitesCacheSize(Int32(ASPanelUX.topSitesCacheSize))
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationProfileDidFinishSyncing, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationDynamicFontChanged, object: nil)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationProfileDidFinishSyncing, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadTopSites()

        reloadRecentHistory()

        view.addSubview(tableView)
        tableView.snp_makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
    }

    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.topSiteHandler.currentTraits = self.traitCollection
    }

}

// MARK: -  Section management
extension ActivityStreamPanel {

    enum Section: Int {
        case TopSites
        case History

        static let count = 2

        var title: String? {
            switch self {
            case .History: return "Recent Activity"
            case .TopSites: return nil
            }
        }

        var headerHeight: CGFloat {
            switch self {
            case .History: return 40
            case .TopSites: return 0
            }
        }

        func cellHeight(traits: UITraitCollection) -> CGFloat {
            switch self {
            case .History: return UITableViewAutomaticDimension
            case .TopSites:
                if traits.horizontalSizeClass == .Compact && traits.verticalSizeClass == .Regular {
                    return ASPanelUX.TopSiteDoubleRowHeight
                } else {
                    return ASPanelUX.TopSiteSingleRowHeight
                }
            }
        }

        var headerView: UIView? {
            switch self {
            case .History:
                let view = ASHeaderView()
                view.title = "Recent Activity"
                return view
            case .TopSites:
                return nil
            }
        }

        var cellIdentifier: String {
            switch self {
            case .TopSites: return "TopSite"
            case .History: return "Cell"
            }
        }

        init(at indexPath: NSIndexPath) {
            self.init(rawValue: indexPath.section)!
        }

        init(_ section: Int) {
            self.init(rawValue: section)!
        }
    }

}

// MARK: -  Tableview Delegate
extension ActivityStreamPanel: UITableViewDelegate {

    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Section(section).headerHeight
    }

    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return Section(section).headerView
    }

    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return Section(indexPath.section).cellHeight(self.traitCollection)
    }

    func showSiteWithURL(url: NSURL) {
        let visitType = VisitType.Bookmark
        homePanelDelegate?.homePanel(self, didSelectURL: url, visitType: visitType)
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(indexPath.section) {
        case .History:
            let site = self.history[indexPath.row]
            showSiteWithURL(NSURL(string:site.url)!)
        case .TopSites:
            return
        } 
    }

}

// MARK: - Tableview Data Source
extension ActivityStreamPanel: UITableViewDataSource {

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(section) {
            case .TopSites:
                return topSiteHandler.content.isEmpty ? 0 : 1
            case .History:
                 return self.history.count
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let identifier = Section(indexPath.section).cellIdentifier
        let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath)

        switch Section(indexPath.section) {
        case .TopSites:
            return configureTopSitesCell(cell, forIndexPath: indexPath)
        case .History:
            return configureHistoryItemCell(cell, forIndexPath: indexPath)
        }
    }

    func configureTopSitesCell(cell: UITableViewCell, forIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let topSiteCell = cell as! ASHorizontalScrollCell
        topSiteCell.delegate = self.topSiteHandler
        return cell
    }

    func configureHistoryItemCell(cell: UITableViewCell, forIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let simpleHighlightCell = cell as! SimpleHighlightCell
        let site = history[indexPath.row]
        simpleHighlightCell.configureSimpleHighlightCell(site)
        return simpleHighlightCell
    }

}

// MARK: - Data Management
extension ActivityStreamPanel {

    func notificationReceived(notification: NSNotification) {
        switch notification.name {
        case NotificationProfileDidFinishSyncing:
            // Only reload top sites if there the cache is dirty since the finish syncing
            // notification is fired everytime the user re-enters the app from the background.
            self.profile.history.areTopSitesDirty(withLimit: ASPanelUX.topSitesCacheSize) >>== { dirty in
                if dirty {
                    self.reloadTopSites()
                }
            }
        case NotificationFirefoxAccountChanged, NotificationPrivateDataClearedHistory, NotificationDynamicFontChanged:
            self.reloadTopSites()
        default:
            log.warning("Received unexpected notification \(notification.name)")
        }
    }

    private func reloadRecentHistory() {
        self.profile.history.getSitesByLastVisit(ASPanelUX.historySize).uponQueue(dispatch_get_main_queue()) { result in
            self.history = result.successValue?.asArray() ?? self.history
            self.tableView.reloadData()
        }
    }

    private func reloadTopSites() {
        invalidateTopSites().uponQueue(dispatch_get_main_queue()) { result in
            let sites = result.successValue ?? []
            self.topSites = sites
            self.topSiteHandler.content = self.topSites
            self.topSiteHandler.urlPressedHandler = { [unowned self] url in
                self.showSiteWithURL(url)
            }
            self.topSiteHandler.currentTraits = self.traitCollection
            self.tableView.reloadData()
        }
    }

    private func invalidateTopSites() -> Deferred<Maybe<[TopSiteItem]>> {
        let frecencyLimit = ASPanelUX.topSitesCacheSize
        return self.profile.history.updateTopSitesCacheIfInvalidated() >>== { dirty in
            if dirty || self.topSites.isEmpty {
                return self.profile.history.getTopSitesWithLimit(frecencyLimit) >>== { topSites in
                    return deferMaybe(topSites.flatMap(self.siteToItem))
                }
            }
            return deferMaybe(self.topSites)
        }
    }

    private func siteToItem(site: Site?) -> TopSiteItem? {
        guard let site = site else {
            return nil
        }

        guard let faviconURL = site.icon?.url else {
            return TopSiteItem(urlTitle: site.tileURL.extractDomainName(), faviconURL: nil, siteURL: site.tileURL)
        }

        return TopSiteItem(urlTitle: site.tileURL.extractDomainName(), faviconURL: NSURL(string: faviconURL)!, siteURL: site.tileURL)
    }
}

// MARK: - HomePanel Protocol
extension ActivityStreamPanel: HomePanel {

    func endEditing() {

    }

}

// MARK: - Section Header View
struct ASHeaderViewUX {
    static let SeperatorColor =  UIColor(rgb: 0xedecea)
    static let TextFont = DynamicFontHelper.defaultHelper.DefaultSmallFontBold
    static let SeperatorHeight = 1
    static let Insets: CGFloat = 20
    static let TitleTopInset: CGFloat = 5
}

class ASHeaderView: UIView {
    lazy private var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.text = self.title
        titleLabel.textColor = UIColor.grayColor()
        titleLabel.font = ASHeaderViewUX.TextFont
        return titleLabel
    }()

    var title: String = "" {
        willSet(newTitle) {
            titleLabel.text = newTitle
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(titleLabel)

        titleLabel.snp_makeConstraints { make in
            make.edges.equalTo(self).offset(UIEdgeInsets(top: ASHeaderViewUX.TitleTopInset, left: ASHeaderViewUX.Insets, bottom: 0, right: -ASHeaderViewUX.Insets))
        }

        let seperatorLine = UIView()
        seperatorLine.backgroundColor = ASHeaderViewUX.SeperatorColor
        addSubview(seperatorLine)
        seperatorLine.snp_makeConstraints { make in
            make.height.equalTo(ASHeaderViewUX.SeperatorHeight)
            make.leading.equalTo(self.snp_leading)
            make.trailing.equalTo(self.snp_trailing)
            make.top.equalTo(self.snp_top)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}