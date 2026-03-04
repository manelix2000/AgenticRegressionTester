# Common Test Scenarios for {{PROJECT_NAME}}

This file contains common testing scenarios specific to **{{PROJECT_NAME}}**. Edit this file to add your app's specific test paths and user journeys.

## Navigation Paths and Elements for interesting screens

### Home Screen or Mosaic Screen
- Location: App launch default screen, or clicking anywhere the tabbar item with identifier `showcases_brands`
- Key Elements:
  - label: `Marcas`
  - label: `Lojas`
  - label: `Femenino`
  - label: `Masculino`
  - identifier: any child element from parent with identifier starting `scrollview-`

### My Account Screen
- Location: Clicking anywhere the tabbar item with identifier `showcases_myaccount`
- Key Elements:
  - identifier: `myaccount_orders`
  - identifier: `myaccount_personaldata`
  - identifier: `myaccount_favorites`
  - identifier: `common_help`
  - identifier: `myaccount_vouchersandpromos`
  - identifier: `mgm_inviteandwin_title`
  - identifier: `myaccount_premium`
  - identifier: `myaccount_notificationcenter`
  - identifier: `myaccount_legal_title`
  - identifier: `transparency_channel`
  - identifier: `delete_account`
  - identifier: `logout_cell`
  - identifier: `mypremium_conditions_title`
  - identifier: `myaccount_legal_termsuse`
  - identifier: `myaccount_legal_cookies`
  - identifier: `mypromotions_title`
  - identifier: `myvouchers_title`
  - identifier: `mgm_conditions_title`
  - identifier: `mgm_myinvitations_title`
  - identifier: `mypersonaldata_title`
  - identifier: `myaddresses_title`
  - identifier: `mypaymentmethods_title`

### Catalog Screen
- Location: Clicking anywhere the tabbar item with identifier `showcases_catalog`
- Key Elements:
  - identifier: `catalog_women`
  - identifier: `catalog_men`
  - identifier: `catalog_baby_kids`
  - identifier: `catalog_home_decor`

### Campaign Screen
- Location: Clicking on home screen on any child item from parent with identifier starting `scrollview-`
- Key Elements:
  - identifier: any element starting with `subcategory`
  - identifier: any element starting with `category`

### PLP Screen
- Location: Clicking on campaign screen on any item with identifier starting `subcategory-`
- Key Elements:
  - identifier: any child element from parent with identifier starting with `searchresultsgrid-`
  - identifier: `product_add_to_cart`

### PDP Screen
- Location: Clicking on PLP screen on any child item from parent with identifier starting `searchresultsgrid-`
- Key Elements:
  - identifier: `product_add_to_cart`
  
### Basket Screen
- Location: Clicking anywhere the navigation bar button with identifier `basket_button`
- Key Elements:
  - identifier: `whatever`

### Placeholder Sample Screen (not real)
- Location: Clicking the whatever with identifier `whatever`
- Key Elements:
  - identifier: `whatever`


---

## Common User Journeys

### 1. Login Flow with a fresh install

```markdown
**Path**: Launch → Login Screen → Enter Credentials → Home Screen

**Steps**:
1. Launch app
2. Accept system alerts
3. Continue onboarding screens
4. Click the sign in button
5. Wait for login screen
6. Tap username field
7. Type username
8. Tap password field
9. Type password
10. Tap login button
11. Wait and verify home screen appears

```

**Expected Result**: User is logged in and home screen appears

**Test errors**:
- Unexpected errors
- Invalid credentials errors

### 2. Login Flow with an existing session

```markdown
**Path**: Launch → Home Screen → Logout → Login Screen → Enter Credentials → Home Screen

**Steps**:
1. Launch app
2. Wait for home screen
3. Click on my account and logout
4. Click the sign in button
5. Wait for login screen
6. Tap username field
7. Type username
8. Tap password field
9. Type password
10. Tap login button
11. Wait and verify home screen appears

```

**Expected Result**: User is logged in and home screen appears

**Test errors**:
- Unexpected errors
- Invalid credentials errors

---

## Test Data

### Valid Test Users
- Username: `john@example.com`, Password: `mypassword`

### Invalid Test Users
- Invalid email: `notanemail`
- Empty password: ``

---

## Test Error Notes

If there is an alert with title containing the text `error` or an element with a label containing the text `error`, stop the test because it has failed, unless the test goal explicitly looks up an error.

---

