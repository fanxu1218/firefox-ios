/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import UIKit
import Deferred
import Storage
import WebImage


// MARK: -  Lifecycle
struct ASPanelUX {
    static let backgroundColor = UIColor(white: 1.0, alpha: 0.5)
    static let topSitesCacheSize = 20
    static let historySize = 10
}

class ActivityStreamPanel: UIViewController, UICollectionViewDelegate {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    let profile: Profile

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

    var topSiteHandler = ASHorizontalScrollSource()

    //once things get fleshed out we can refactor and find a better home for these
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
        refreshTopSites(ASPanelUX.topSitesCacheSize)
        
        reloadRecentHistoryWithLimit(ASPanelUX.historySize)

        view.addSubview(tableView)
        tableView.snp_makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
    }

    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        self.topSiteHandler.currentTraits = self.traitCollection
    }

}

// MARK: -  Section management
extension ActivityStreamPanel {
    enum Section: Int {
        case topSites
        case history

        static let count = 2

        var title: String? {
            switch self {
            case .history: return "Recent Activity"
            default: return nil
            }
        }

        var headerHeight: CGFloat {
            switch self {
            case .history: return 40
            default: return 0
            }
        }

        var headerView: UIView? {
            switch self {
            case .history:
                let view = ASHeaderView()
                view.title = "Recent Activity"
                return view
            default:
                return nil
            }
        }

        var cellIdentifier: String {
            switch self {
            case .topSites: return "TopSite"
            default: return "Cell"
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

// MARK: -  Header Views
extension ActivityStreamPanel {

    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Section(section).headerHeight
    }

    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return Section(section).headerView
    }
}

// MARK: - Tableview management
extension ActivityStreamPanel: UITableViewDelegate, UITableViewDataSource {

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(section) {
            case .topSites:
                if !topSiteHandler.content.isEmpty {
                    return 1
                } else {
                    return 0
                }
            case .history:
                 return self.history.count
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let identifier = Section(indexPath.section).cellIdentifier
        let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath)

        switch Section(indexPath.section) {
            case .topSites:
                return configureTopSitesCell(cell, forIndexPath: indexPath)
            default:
                return configureHistoryItemCell(cell, forIndexPath: indexPath)
        }
    }

    func configureTopSitesCell(cell: UITableViewCell, forIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let topSiteCell = cell as! ASHorizontalScrollCell
        // The topSiteCell needs a refrence to the tableview because it needs to alert the tableView to relayout once topsites finishes loading.
        topSiteCell.parentTableView = self.tableView
        topSiteCell.setDelegate(self.topSiteHandler)
        return cell
    }

    func configureHistoryItemCell(cell: UITableViewCell, forIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let simpleHighlightCell = cell as! SimpleHighlightCell
        let site = history[indexPath.row]
        simpleHighlightCell.configureSimpleHighlightCell(site)
        return simpleHighlightCell
    }

    func showSiteWithURL(url: NSURL) {
        let visitType = VisitType.Bookmark
        homePanelDelegate?.homePanel(self, didSelectURL: url, visitType: visitType)
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(indexPath.section) {
        case .history:
            let site = self.history[indexPath.row]
            showSiteWithURL(NSURL(string:site.url)!)
        default:
            return
        }
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
                    self.refreshTopSites(ASPanelUX.topSitesCacheSize)
                }
            }
        case NotificationFirefoxAccountChanged, NotificationPrivateDataClearedHistory, NotificationDynamicFontChanged:
            self.refreshTopSites(ASPanelUX.topSitesCacheSize)
        default:
            // no need to do anything at all
            print("Dont have this notification type")
        }
    }

    private func refreshTopSites(frecencyLimit: Int) {
        dispatch_async(dispatch_get_main_queue()) {
            // Reload right away with whatever is in the cache, then check to see if the cache is invalid.
            // If it's invalid, invalidate the cache and requery. This allows us to always show results
            // immediately while also loading up-to-date results asynchronously if needed.
            self.reloadTopSitesWithLimit(frecencyLimit) >>> {
                self.profile.history.updateTopSitesCacheIfInvalidated() >>== { dirty in
                    if dirty {
                        self.reloadTopSitesWithLimit(frecencyLimit)
                    }
                }
            }
        }
    }

    private func reloadTopSitesWithLimit(limit: Int) -> Success {
        return self.profile.history.getTopSitesWithLimit(limit).bindQueue(dispatch_get_main_queue()) { result in
            if let data = result.successValue {
                self.topSites = data.asArray().map { site in
                    if let favURL = site.icon?.url {
                        return TopSiteItem(urlTitle: site.tileURL.extractDomainName(), faviconURL: NSURL(string: favURL)!, siteURL: site.tileURL)
                    }
                    return TopSiteItem(urlTitle: site.tileURL.extractDomainName(), faviconURL: nil, siteURL: site.tileURL)
                }
                self.topSiteHandler.content = self.topSites
                self.topSiteHandler.urlPressedHandler = { [unowned self] url in
                    self.showSiteWithURL(url)
                }
                self.topSiteHandler.currentTraits = self.traitCollection
                self.tableView.reloadData()
            }
            return succeed()
        }
    }

    private func reloadRecentHistoryWithLimit(limit: Int) -> Success {
        return self.profile.history.getSitesByLastVisit(limit).bindQueue(dispatch_get_main_queue()) { result in
            if let data = result.successValue {
                self.history = data.asArray()
                self.tableView.reloadData()
            }
            return succeed()
        }
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