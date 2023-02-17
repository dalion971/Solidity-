// SPDX-License-Identifier: MIT
/* 
    Author By Dalion
    实现的功能
    1：创建多个募捐者，创建多个捐款者，且每个地址在合约中仅允许创建一次
    2：捐款者可以给募捐者捐款，当捐款数量超过募捐目标时，额外的资金会被允许退回。
    3：当捐款完成时，募捐者可以从合约提款。任何时刻捐款者都可以将额外的资金从合约中提取
    4：任何人可以看到募捐者被哪些人捐款，捐款数量是多少
    5：任何人可以看到捐款者对哪些募捐者分别捐款多少
    6: 同一个地址只能是募捐者 or 捐款者之一
*/
pragma solidity >=0.8.0 <0.9.0;
import "hardhat/console.sol";

contract CrowFunding {

    struct donater
    {
        address donater_address;        
        uint ammount; // 捐献资金的数量
        uint needer_me_cnt;

        mapping(uint => Entry) neederme_index_to_needer_index_map;
        mapping(uint => uint) needer_index_receive_money_map;      
    }


    // 募集资金
    struct Entry{
        uint index;
        bool is_used;
    }
    struct needer
    {
        address needer_address;        
        uint fund_goal; // 需要募集多少钱
        uint ammount; // 当前所有资金
        uint donate_me_cnt;
        mapping(uint => Entry) donateme_index_to_donater_index_map;
        mapping(uint => uint) doneter_index_donate_money_tome_map;       
        bool is_finished;   
    }


    // 多个募捐人
    uint needer_cnt;
    mapping(uint => needer) needer_map;
    // 多个捐款人
    uint donater_cnt;
    mapping(uint => donater) donater_map;

    // 不允许重复创建募捐人 捐款人，一个人地址可以同时是募捐人也可以是捐款者 并保存其id
    mapping(address => uint) needer_addr_map;
    mapping(address => uint) donater_addr_map;

    mapping(uint => bool) is_needer_or_donater_map;
    // 合约保存的资金，当捐款不需要时，允许捐款者取回现金
    // 优化为一个map
    mapping(address => uint) withdraw_money_map;

    modifier onlyNeeder(uint index)
    {
        require(index > 0 && index <= needer_cnt);
        require(msg.sender == needer_map[index].needer_address);
        _;
    }

    modifier onlyDonater(uint donater_index)
    {
        require(donater_index > 0 && donater_index <= donater_cnt);
        require(msg.sender == donater_map[donater_addr_map[msg.sender]].donater_address);
        _;
    }

    function newNeeder(address addr, uint goal) public
    {
        require(addr != address(0));
        require(goal > 0);
        require(needer_addr_map[addr] == 0, "Had Existed Needer");
        require(is_needer_or_donater_map[needer_cnt] == false, "Only Needer Or Donater");
        needer_addr_map[addr] = ++needer_cnt;

        needer storage new_needer = needer_map[needer_cnt];
        new_needer.needer_address = addr;
        new_needer.fund_goal = goal;
        new_needer.ammount = 0;
        new_needer.donate_me_cnt = 0;
        new_needer.is_finished = false;
        is_needer_or_donater_map[needer_cnt] = true;
    }

    function newDonater(address addr) public
    {
        require(addr != address(0));
        require(donater_addr_map[addr] == 0, "Had Existed Donater");
        require(is_needer_or_donater_map[needer_cnt] == false, "Only Needer Or Donater");

        donater_addr_map[addr] = ++donater_cnt;
        donater storage new_donater = donater_map[donater_cnt];
        new_donater.donater_address = addr;
        new_donater.ammount = 0;
        new_donater.needer_me_cnt = 0;
        is_needer_or_donater_map[needer_cnt] = true;

    }

    function getNeederIndex(address addr) public view returns(uint)
    {
        return needer_addr_map[addr];
    }

    function getDonaterIndex(address addr) public view returns(uint)
    {
        return donater_addr_map[addr];
    }
    // 查看都谁对needer_index捐款
    function getNeederWatchDonate(uint needer_index) public view
    {
        uint num_donater = needer_map[needer_index].donate_me_cnt;
        for(uint index = 1; index <= num_donater; index++)
        {
            uint donate_index = needer_map[needer_index].donateme_index_to_donater_index_map[index].index;
            uint donate_money = needer_map[needer_index].doneter_index_donate_money_tome_map[donate_index];
            console.log("donate_index:%s, addr:%s, donate:%d", donate_index, donater_map[donate_index].donater_address,  donate_money);
        }
    }
    // 查看donate_index都对谁捐款
    function getDonaterWatchDonate(uint donate_index) public view
    {
        uint num_needer = donater_map[donate_index].needer_me_cnt;
        for(uint index = 1; index <= num_needer; index++)
        {
            uint needer_index = donater_map[donate_index].neederme_index_to_needer_index_map[index].index;
            uint donate_money = donater_map[donate_index].needer_index_receive_money_map[needer_index];
            console.log("needer_index:%s, addr:%s, donate:%d", needer_index, needer_map[needer_index].needer_address,  donate_money);
        }
    }

    // 捐赠者向哪个neederid 捐了多少
    event DonateEvent(address, uint, uint);
    // function fund 捐赠
    function fund(uint needer_index) onlyDonater(needer_index) public payable
    {
        require(msg.value > 0, "value < 0");
        needer storage ndr = needer_map[needer_index];

        if(ndr.is_finished == true || (ndr.ammount >= ndr.fund_goal && ndr.is_finished == false))
        {
            // 捐款以满足不需要捐款
            withdraw_money_map[msg.sender] += msg.value;
            return;
        }
 
        // 当捐钱者捐的前超出需要募捐数时
        uint donate_ammount = msg.value > ndr.fund_goal - ndr.ammount ? ndr.fund_goal - ndr.ammount : msg.value;
        uint return_ammout = msg.value - donate_ammount;

        // 更新被募捐人的结构
        ndr.ammount += donate_ammount;
        // 记录募捐者 并且 募捐数量++
        
        uint donater_index = donater_addr_map[msg.sender];
        
        Entry storage ety = ndr.donateme_index_to_donater_index_map[++ndr.donate_me_cnt];
        if(ety.is_used == false)
        {
            ety.is_used = true;
            ety.index = donater_index;
        }
        ndr.doneter_index_donate_money_tome_map[donater_index] += donate_ammount;
        


        //donater storage dtr = donater_map[donater_index];
        //ndr.donater_donate_map[++ndr.donater_me_cnt][donater_index] = dtr;

        //记录捐款人结构
        donater storage dtr = donater_map[donater_index];
        Entry storage ety_dtr = dtr.neederme_index_to_needer_index_map[++dtr.needer_me_cnt];
        if(ety_dtr.is_used == false)
        {
            ety_dtr.is_used = true;
            ety_dtr.index = needer_index;
        }
        dtr.needer_index_receive_money_map[needer_index] += donate_ammount;

        // 判断募集是否完成
        if(ndr.ammount >= ndr.fund_goal)
        {
            ndr.is_finished = true;
        }
        // 允许募捐者从合约提款
        withdraw_money_map[ndr.needer_address] += donate_ammount;
        // 募捐者返回款放到后面 因为可能有多次退款 用+=
        withdraw_money_map[msg.sender] += return_ammout;

        emit DonateEvent(msg.sender, needer_index, donate_ammount);
    }

    event NeederWithDrawEvent(address, uint, uint);

    // 募捐完成才能提款, 并且一次提款所有
    function withdrawNeeder(uint needer_index) onlyNeeder(needer_index) public
    {
        needer storage ndr = needer_map[needer_index];
        require(ndr.is_finished == true);
 
        uint ammount = withdraw_money_map[ndr.needer_address];
        withdraw_money_map[ndr.needer_address] = 0;
        payable(msg.sender).transfer(ammount);
        // 可选从募捐列表清除，不过没必要
        emit NeederWithDrawEvent(ndr.needer_address, needer_index, ammount);
    }

    event DonaterWithDrawEvent(address, uint);


    // 捐献者提款, 并且一次提款所有
    function withdrawDonater(uint donater_index) onlyDonater(donater_index) public
    {
        // 仅允许本人提款
        uint ammount = withdraw_money_map[msg.sender];
        withdraw_money_map[msg.sender] = 0;
        payable(msg.sender).transfer(ammount);
        // 可选从募捐列表清除，不过没必要
        emit DonaterWithDrawEvent(msg.sender, ammount);
    }

    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }





}